using Gdk;
using Gee;
using Gtk;
using Pango;

using Xmpp;
using Dino.Entities;

namespace Dino.Ui {

public class ConversationSelector : Box {

    public signal void conversation_selected(Conversation conversation);

    private ListBox conversation_list_box = new ListBox() { hexpand=true };
    private ListBox contacts_list_box = new ListBox() { hexpand=true };
    private Revealer contacts_revealer = new Revealer() { transition_type=RevealerTransitionType.SLIDE_LEFT };
    private Separator contacts_separator = new Separator(Orientation.VERTICAL);
    private SearchEntry people_search_entry = new SearchEntry();
    private string people_search_term = "";
    private bool people_panel_enabled = false;

    private StreamInteractor stream_interactor;
    private HashMap<Conversation, ConversationSelectorRow> rows = new HashMap<Conversation, ConversationSelectorRow>(Conversation.hash_func, Conversation.equals_func);
    private HashMap<string, ContactQuickRow> contact_rows = new HashMap<string, ContactQuickRow>();

    private class ContactQuickRow : ListBoxRow {
        public Account account { get; construct; }
        public Jid jid { get; construct; }
        public string group_name { get; construct; }
        public string display_name { get; construct; }
        private Image status_icon;

        public ContactQuickRow(Account account, Jid jid, string group_name, string display_name) {
            Object(account: account, jid: jid, group_name: group_name, display_name: display_name);
            add_css_class("dino-people-row");

            status_icon = new Image.from_icon_name("dino-status-online") {
                pixel_size = 14,
                valign = Align.CENTER
            };

            var name_label = new Label(display_name) {
                xalign = 0,
                ellipsize = EllipsizeMode.END
            };
            name_label.add_css_class("dino-people-name");

            var jid_label = new Label(jid.to_string()) {
                xalign = 0,
                ellipsize = EllipsizeMode.END
            };
            jid_label.add_css_class("dim-label");
            jid_label.add_css_class("caption");

            var content_box = new Box(Orientation.VERTICAL, 1) {
                margin_start = 8,
                margin_end = 12,
                margin_top = 6,
                margin_bottom = 6
            };
            content_box.append(name_label);
            content_box.append(jid_label);

            var row_box = new Box(Orientation.HORIZONTAL, 8) {
                margin_start = 6,
                margin_end = 0,
                margin_top = 0,
                margin_bottom = 0
            };
            row_box.append(status_icon);
            row_box.append(content_box);
            set_child(row_box);
        }

        public void set_presence_icon(string icon_name) {
            status_icon.set_from_icon_name(icon_name);
        }
    }

    private string contact_key(Account account, Jid jid, string group_name) {
        return @"$(account.id):$(jid.bare_jid.to_string()):$group_name";
    }

    public void set_people_panel_enabled(bool enabled) {
        people_panel_enabled = enabled;
        update_contacts_visibility();
    }

    public void toggle_people_panel() {
        set_people_panel_enabled(!people_panel_enabled);
    }

    private void update_contacts_visibility() {
        contacts_revealer.reveal_child = people_panel_enabled;
        contacts_separator.visible = people_panel_enabled;
    }

    private Gee.List<string> get_groups_from_roster_item(Roster.Item item) {
        var groups = new ArrayList<string>();
        foreach (StanzaNode group_node in item.stanza_node.sub_nodes) {
            if (group_node.name != "group") continue;
            string? group_name = group_node.get_string_content();
            if (group_name != null && group_name.strip() != "") {
                groups.add(group_name.strip());
            }
        }
        if (groups.is_empty) {
            groups.add(_("Ungrouped"));
        }
        return groups;
    }

    private void remove_contact_rows_for(Account account, Jid jid) {
        var remove_keys = new ArrayList<string>();
        string prefix = @"$(account.id):$(jid.bare_jid.to_string()):";
        foreach (string key in contact_rows.keys) {
            if (key.has_prefix(prefix)) {
                remove_keys.add(key);
            }
        }
        foreach (string key in remove_keys) {
            ContactQuickRow row;
            if (contact_rows.unset(key, out row)) {
                contacts_list_box.remove(row);
            }
        }
        update_contacts_visibility();
    }

    private void add_or_update_contact_rows(Account account, Roster.Item item) {
        Jid? jid = item.jid;
        if (jid == null) return;

        remove_contact_rows_for(account, jid);

        string display_name = item.name != null && item.name != "" ? item.name : jid.bare_jid.to_string();
        string presence_icon = get_contact_presence_icon(account, jid.bare_jid);
        foreach (string group_name in get_groups_from_roster_item(item)) {
            ContactQuickRow row = new ContactQuickRow(account, jid.bare_jid, group_name, display_name);
            row.set_presence_icon(presence_icon);
            contact_rows[contact_key(account, jid, group_name)] = row;
            contacts_list_box.append(row);
        }

        contacts_list_box.invalidate_sort();
        contacts_list_box.invalidate_headers();
        update_contacts_visibility();
    }

    private string get_contact_presence_icon(Account account, Jid bare_jid) {
        Gee.List<Jid>? full_jids = stream_interactor.get_module(PresenceManager.IDENTITY).get_full_jids(bare_jid, account);
        if (full_jids == null || full_jids.size == 0) {
            return "dino-status-away";
        }

        var statuses = new ArrayList<string>();
        foreach (Jid full_jid in full_jids) {
            string? show = stream_interactor.get_module(PresenceManager.IDENTITY).get_last_show(full_jid, account);
            if (show != null) statuses.add(show);
        }

        if (statuses.contains(Xmpp.Presence.Stanza.SHOW_DND)) return "dino-status-dnd";
        if (statuses.contains(Xmpp.Presence.Stanza.SHOW_CHAT)) return "dino-status-chat";
        if (statuses.contains(Xmpp.Presence.Stanza.SHOW_ONLINE)) return "dino-status-online";
        if (statuses.contains(Xmpp.Presence.Stanza.SHOW_AWAY) || statuses.contains(Xmpp.Presence.Stanza.SHOW_XA)) return "dino-status-away";

        return "dino-status-online";
    }

    private void refresh_contact_presence(Account account, Jid jid) {
        string prefix = @"$(account.id):$(jid.bare_jid.to_string()):";
        string icon_name = get_contact_presence_icon(account, jid.bare_jid);
        foreach (string key in contact_rows.keys) {
            if (!key.has_prefix(prefix)) continue;
            ContactQuickRow row = contact_rows[key];
            row.set_presence_icon(icon_name);
        }
    }

    private void rebuild_contacts_for_account(Account account) {
        foreach (Roster.Item item in stream_interactor.get_module(RosterManager.IDENTITY).get_roster(account)) {
            add_or_update_contact_rows(account, item);
        }
    }

    public ConversationSelector init(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;

        conversation_list_box.add_css_class("navigation-sidebar");
        contacts_list_box.add_css_class("navigation-sidebar");
        contacts_list_box.add_css_class("dino-people-list");

        stream_interactor.get_module(ConversationManager.IDENTITY).conversation_activated.connect(add_conversation);
        stream_interactor.get_module(ConversationManager.IDENTITY).conversation_deactivated.connect(remove_conversation);
        stream_interactor.get_module(ContentItemStore.IDENTITY).new_item.connect(on_content_item_received);
        stream_interactor.account_added.connect((account) => rebuild_contacts_for_account(account));
        stream_interactor.account_removed.connect((account) => {
            var remove_keys = new ArrayList<string>();
            string prefix = @"$(account.id):";
            foreach (string key in contact_rows.keys) {
                if (key.has_prefix(prefix)) remove_keys.add(key);
            }
            foreach (string key in remove_keys) {
                ContactQuickRow row;
                if (contact_rows.unset(key, out row)) {
                    contacts_list_box.remove(row);
                }
            }
            update_contacts_visibility();
        });

        stream_interactor.get_module(RosterManager.IDENTITY).updated_roster_item.connect((account, jid, roster_item) => {
            add_or_update_contact_rows(account, roster_item);
        });
        stream_interactor.get_module(RosterManager.IDENTITY).removed_roster_item.connect((account, jid, roster_item) => {
            remove_contact_rows_for(account, jid);
        });
        stream_interactor.get_module(PresenceManager.IDENTITY).show_received.connect((jid, account) => {
            refresh_contact_presence(account, jid);
        });
        stream_interactor.get_module(PresenceManager.IDENTITY).received_offline_presence.connect((jid, account) => {
            refresh_contact_presence(account, jid);
        });

        Timeout.add_seconds(60, () => {
            foreach (ConversationSelectorRow row in rows.values) row.update();
            return true;
        });

        foreach (Conversation conversation in stream_interactor.get_module(ConversationManager.IDENTITY).get_active_conversations()) {
            add_conversation(conversation);
        }
        foreach (Account account in stream_interactor.get_accounts()) {
            rebuild_contacts_for_account(account);
        }

        update_contacts_visibility();
        return this;
    }

    construct {
        orientation = Orientation.HORIZONTAL;
        spacing = 0;

        var contacts_title = new Label(_("People")) {
            xalign = 0,
            margin_start = 12,
            margin_end = 12,
            margin_top = 8,
            margin_bottom = 2
        };
        contacts_title.add_css_class("title-4");
        contacts_title.add_css_class("dim-label");

        var contacts_box = new Box(Orientation.VERTICAL, 0);
        contacts_box.width_request = 260;
        contacts_box.add_css_class("dino-people-panel");
        contacts_box.append(contacts_title);

        people_search_entry.placeholder_text = _("Search people");
        people_search_entry.margin_start = 12;
        people_search_entry.margin_end = 12;
        people_search_entry.margin_bottom = 6;
        people_search_entry.changed.connect(() => {
            people_search_term = people_search_entry.text.strip().down();
            contacts_list_box.invalidate_filter();
            contacts_list_box.invalidate_headers();
        });
        contacts_box.append(people_search_entry);

        var contacts_scrolled = new ScrolledWindow() {
            hscrollbar_policy = PolicyType.NEVER,
            vexpand = true
        };
        contacts_scrolled.set_child(contacts_list_box);
        contacts_box.append(contacts_scrolled);

        contacts_revealer.child = contacts_box;
        contacts_revealer.hexpand = false;

        contacts_separator.visible = false;

        var conversations_scrolled = new ScrolledWindow() {
            hscrollbar_policy = PolicyType.NEVER,
            vexpand = true
        };
        conversations_scrolled.set_child(conversation_list_box);
        append(conversations_scrolled);
        append(contacts_separator);
        append(contacts_revealer);

        conversation_list_box.set_sort_func(sort);
        contacts_list_box.set_sort_func(sort_contacts);
        contacts_list_box.set_header_func(update_contact_header);
        contacts_list_box.set_filter_func(filter_contacts);

        realize.connect(() => {
            ListBoxRow? first_row = conversation_list_box.get_row_at_index(0);
            if (first_row != null) {
                conversation_list_box.select_row(first_row);
                row_activated(first_row);
            }
        });

        conversation_list_box.row_activated.connect(row_activated);
        contacts_list_box.row_activated.connect((row) => {
            ContactQuickRow? contact_row = row as ContactQuickRow;
            if (contact_row == null) return;

            Conversation conversation = stream_interactor.get_module(ConversationManager.IDENTITY)
                    .create_conversation(contact_row.jid, contact_row.account, Conversation.Type.CHAT);
            stream_interactor.get_module(ConversationManager.IDENTITY).start_conversation(conversation);
            on_conversation_selected(conversation);
            conversation_selected(conversation);
        });
    }

    public void row_activated(ListBoxRow r) {
        ConversationSelectorRow? row = r as ConversationSelectorRow;
        if (row != null) {
            conversation_selected(row.conversation);
        }
    }

    public void on_conversation_selected(Conversation conversation) {
        if (!rows.has_key(conversation)) {
            add_conversation(conversation);
        }
        conversation_list_box.select_row(rows[conversation]);
    }

    private void on_content_item_received(ContentItem item, Conversation conversation) {
        if (rows.has_key(conversation)) {
            conversation_list_box.invalidate_sort();
        }
    }

    private void add_conversation(Conversation conversation) {
        ConversationSelectorRow row;
        if (!rows.has_key(conversation)) {
            conversation.notify["pinned"].connect(conversation_list_box.invalidate_sort);

            row = new ConversationSelectorRow(stream_interactor, conversation);
            rows[conversation] = row;
            conversation_list_box.append(row);
            row.main_revealer.set_reveal_child(true);

            // Set up drag motion behaviour (select conversation after timeout)
            DropControllerMotion drop_motion_controller = new DropControllerMotion();
            uint drag_timeout = 0;
            drop_motion_controller.motion.connect((x, y) => {
                if (drag_timeout != 0) return;
                drag_timeout = Timeout.add(200, () => {
                    conversation_selected(conversation);
                    drag_timeout = 0;
                    return false;
                });
            });
            drop_motion_controller.leave.connect(() => {
                if (drag_timeout != 0) {
                    Source.remove(drag_timeout);
                    drag_timeout = 0;
                }
            });
            row.add_controller(drop_motion_controller);
        }
        conversation_list_box.invalidate_sort();
    }

    private void select_fallback_conversation(Conversation conversation) {
        if (conversation_list_box.get_selected_row() == rows[conversation]) {
            int index = rows[conversation].get_index();
            ListBoxRow? next_select_row = conversation_list_box.get_row_at_index(index + 1);
            if (next_select_row == null) {
                next_select_row = conversation_list_box.get_row_at_index(index - 1);
            }
            if (next_select_row != null) {
                conversation_list_box.select_row(next_select_row);
                row_activated(next_select_row);
            }
        }
    }

    private async void remove_conversation(Conversation conversation) {
        select_fallback_conversation(conversation);
        if (rows.has_key(conversation)) {
            conversation.notify["pinned"].disconnect(conversation_list_box.invalidate_sort);

            ConversationSelectorRow conversation_row;
            rows.unset(conversation, out conversation_row);

            yield conversation_row.colapse();
            conversation_list_box.remove(conversation_row);
        }
    }

    public void loop_conversations(bool backwards) {
        if (rows.size == 0 || conversation_list_box.get_selected_row() == null) return;

        int index = conversation_list_box.get_selected_row().get_index();
        int new_index = ((index + (backwards ? -1 : 1)) + rows.size) % rows.size;
        ListBoxRow? next_select_row = conversation_list_box.get_row_at_index(new_index);
        if (next_select_row != null) {
            conversation_list_box.select_row(next_select_row);
            row_activated(next_select_row);
        }
    }

    private int sort_contacts(ListBoxRow row1, ListBoxRow row2) {
        ContactQuickRow c1 = row1 as ContactQuickRow;
        ContactQuickRow c2 = row2 as ContactQuickRow;
        if (c1 == null || c2 == null) return 0;

        int group_comp = c1.group_name.collate(c2.group_name);
        if (group_comp != 0) return group_comp;

        int name_comp = c1.display_name.collate(c2.display_name);
        if (name_comp != 0) return name_comp;

        return c1.jid.to_string().collate(c2.jid.to_string());
    }

    private bool filter_contacts(ListBoxRow row) {
        ContactQuickRow contact = row as ContactQuickRow;
        if (contact == null) return true;

        if (people_search_term == "") return true;

        if (contact.display_name.down().contains(people_search_term)) return true;
        if (contact.jid.to_string().down().contains(people_search_term)) return true;
        if (contact.group_name.down().contains(people_search_term)) return true;
        return false;
    }

    private void update_contact_header(ListBoxRow row, ListBoxRow? before) {
        ContactQuickRow current = row as ContactQuickRow;
        if (current == null) {
            row.set_header(null);
            return;
        }

        ContactQuickRow? previous = before as ContactQuickRow;
        if (previous != null && previous.group_name == current.group_name) {
            row.set_header(null);
            return;
        }

        var header_label = new Label(current.group_name) {
            xalign = 0,
            margin_start = 12,
            margin_end = 12,
            margin_top = 8,
            margin_bottom = 2
        };
        header_label.add_css_class("dino-people-group");
        header_label.add_css_class("dim-label");
        row.set_header(header_label);
    }

    private int sort(ListBoxRow row1, ListBoxRow row2) {
        ConversationSelectorRow cr1 = row1 as ConversationSelectorRow;
        ConversationSelectorRow cr2 = row2 as ConversationSelectorRow;
        if (cr1 != null && cr2 != null) {
            Conversation c1 = cr1.conversation;
            Conversation c2 = cr2.conversation;

            int pin_comp = c2.pinned - c1.pinned;
            if (pin_comp != 0) return pin_comp;

            if (c1.last_active == null) return -1;
            if (c2.last_active == null) return 1;
            int comp = c2.last_active.compare(c1.last_active);
            if (comp == 0) {
                return Util.get_conversation_display_name(stream_interactor, c1)
                    .collate(Util.get_conversation_display_name(stream_interactor, c2));
            } else {
                return comp;
            }
        }
        return 0;
    }
}

}
