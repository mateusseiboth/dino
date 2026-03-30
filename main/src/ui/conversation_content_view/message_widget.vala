using Gee;
using Gdk;
using Gtk;
using Pango;
using Xmpp;

using Dino.Entities;

namespace Dino.Ui.ConversationSummary {

public class MessageMetaItem : ContentMetaItem {

    enum AdditionalInfo {
        NONE,
        PENDING,
        DELIVERY_FAILED
    }

    private StreamInteractor stream_interactor;
    private MessageItem message_item;
    public Message.Marked marked { get; set; }
    public Plugins.ConversationItemWidgetInterface outer = null;

    MessageItemEditMode? edit_mode = null;
    ChatTextViewController? controller = null;
    AdditionalInfo additional_info = AdditionalInfo.NONE;

    ulong realize_id = -1;
    ulong marked_notify_handler_id = -1;
    uint pending_timeout_id = -1;

    public Label label = new Label("") { use_markup=true, xalign=0, selectable=true, wrap=true, wrap_mode=Pango.WrapMode.WORD_CHAR, hexpand=true, vexpand=true };
    private Box? content_box = null;
    private Widget active_widget = null;

    public MessageMetaItem(ContentItem content_item, StreamInteractor stream_interactor) {
        base(content_item);
        message_item = content_item as MessageItem;
        this.stream_interactor = stream_interactor;

        stream_interactor.get_module(MessageCorrection.IDENTITY).received_correction.connect(on_updated_item);
        stream_interactor.get_module(MessageDeletion.IDENTITY).item_deleted.connect(on_updated_item);

        label.activate_link.connect(on_label_activate_link);

        Message message = ((MessageItem) content_item).message;
        if (message.direction == Message.DIRECTION_SENT && !(message.marked in Message.MARKED_RECEIVED)) {
            var binding = message.bind_property("marked", this, "marked");
            marked_notify_handler_id = this.notify["marked"].connect(() => {
                // Currently "pending", but not anymore
                if (additional_info == AdditionalInfo.PENDING &&
                        message.marked != Message.Marked.SENDING && message.marked != Message.Marked.UNSENT) {
                    update_label();
                }

                // Currently "error", but not anymore
                if (additional_info == AdditionalInfo.DELIVERY_FAILED && message.marked != Message.Marked.ERROR) {
                    update_label();
                }

                // Currently not error, but should be
                if (additional_info != AdditionalInfo.DELIVERY_FAILED && message.marked == Message.Marked.ERROR) {
                    update_label();
                }

                // Nothing bad can happen anymore
                if (message.marked in Message.MARKED_RECEIVED) {
                    binding.unbind();
                    this.disconnect(marked_notify_handler_id);
                    marked_notify_handler_id = -1;
                }
            });
        }

        update_label();
    }

    private void generate_markup_text(ContentItem item, Label label) {
        MessageItem message_item = item as MessageItem;
        Conversation conversation = message_item.conversation;
        Message message = message_item.message;

        // Get a copy of the markup spans, such that we can modify them
        var markups = new ArrayList<Xep.MessageMarkup.Span>();
        foreach (var markup in message.get_markups()) {
            markups.add(new Xep.MessageMarkup.Span() { types=markup.types, start_char=markup.start_char, end_char=markup.end_char });
        }

        string markup_text = message.body;

        var attrs = new AttrList();
        label.set_attributes(attrs);

        if (markup_text == null) return; // TODO remove

        // Only process messages up to a certain size
        if (markup_text.length > 10000) {
            markup_text = markup_text.substring(0, 10000) + " [" + _("Message too long") + "]";
        }

        bool theme_dependent = false;

        markup_text = Util.remove_fallbacks_adjust_markups(markup_text, message.quoted_item_id > 0, message.get_fallbacks(), markups);

        var bold_attr = Pango.attr_weight_new(Pango.Weight.BOLD);
        var italic_attr = Pango.attr_style_new(Pango.Style.ITALIC);
        var strikethrough_attr = Pango.attr_strikethrough_new(true);

        // Prefix message with name instead of /me
        if (markup_text.has_prefix("/me ")) {
            string display_name = Util.get_participant_display_name(stream_interactor, conversation, message.from);
            markup_text = display_name + " " + markup_text.substring(4);

            foreach (Xep.MessageMarkup.Span span in markups) {
                int length = display_name.char_count() - 4 + 1;
                span.start_char += length;
                span.end_char += length;
            }

            bold_attr.end_index = display_name.length;
            italic_attr.end_index = display_name.length;
            attrs.insert(bold_attr.copy());
            attrs.insert(italic_attr.copy());
        }

        foreach (var markup in markups) {
            foreach (var ty in markup.types) {
                Attribute attr = null;
                switch (ty) {
                    case Xep.MessageMarkup.SpanType.EMPHASIS:
                        attr = Pango.attr_style_new(Pango.Style.ITALIC);
                        break;
                    case Xep.MessageMarkup.SpanType.STRONG_EMPHASIS:
                        attr = Pango.attr_weight_new(Pango.Weight.BOLD);
                        break;
                    case Xep.MessageMarkup.SpanType.DELETED:
                        attr = Pango.attr_strikethrough_new(true);
                        break;
                }
                attr.start_index = markup_text.index_of_nth_char(markup.start_char);
                attr.end_index = markup_text.index_of_nth_char(markup.end_char);
                attrs.insert(attr.copy());
            }
        }

        // Work around pango bug
        markup_text = Util.unbreak_space_around_non_spacing_mark((owned) markup_text);

        if (conversation.type_ == Conversation.Type.GROUPCHAT) {
            markup_text = Util.parse_add_markup_theme(markup_text, conversation.nickname, true, true, true, Util.is_dark_theme(this.label), ref theme_dependent);
        } else {
            markup_text = Util.parse_add_markup_theme(markup_text, null, true, true, true, Util.is_dark_theme(this.label), ref theme_dependent);
        }

        int only_emoji_count = Util.get_only_emoji_count(markup_text);
        if (only_emoji_count != -1) {
            string size_str = only_emoji_count < 5 ? "xx-large" : "large";
            markup_text = @"<span size=\'$size_str\'>" + markup_text + "</span>";
        }

        string dim_color = Util.is_dark_theme(this.label) ? "#BDBDBD" : "#707070";

        if (message.body == "") {
            markup_text = @"<i><span size='small' color='$dim_color'>%s</span></i>".printf(_("Message deleted"));
            theme_dependent = true;
        }
        if (message.edit_to != null) {
            markup_text += @"  <span size='small' color='$dim_color'>(%s)</span>".printf(_("edited"));
            theme_dependent = true;
        }

        // Append message status info
        additional_info = AdditionalInfo.NONE;
        if (message.direction == Message.DIRECTION_SENT && (message.marked == Message.Marked.SENDING || message.marked == Message.Marked.UNSENT)) {
            // Append "pending..." iff message has not been sent yet
            if (message.time.compare(new DateTime.now_utc().add_seconds(-10)) < 0) {
                markup_text += @"  <span size='small' color='$dim_color'>%s</span>".printf(_("pending…"));
                theme_dependent = true;
                additional_info = AdditionalInfo.PENDING;
            } else {
                int time_diff = (- (int) message.time.difference(new DateTime.now_utc()) / 1000);
                if (pending_timeout_id != -1) Source.remove(pending_timeout_id);
                pending_timeout_id = Timeout.add(10000 - time_diff, () => {
                    update_label();
                    pending_timeout_id = -1;
                    return false;
                });
            }
        } else if (message.direction == Message.DIRECTION_SENT && message.marked == Message.Marked.ERROR) {
            // Append "delivery failed" if there was a server error
            string error_color = Util.rgba_to_hex(Util.get_label_pango_color(label, "@error_color"));
            markup_text += "  <span size='small' color='%s'>%s</span>".printf(error_color, _("delivery failed"));
            theme_dependent = true;
            additional_info = AdditionalInfo.DELIVERY_FAILED;
        }

        if (theme_dependent && realize_id == -1) {
            realize_id = label.realize.connect(update_label);
        } else if (!theme_dependent && realize_id != -1) {
            label.disconnect(realize_id);
        }
        label.label = markup_text;
    }

    public void update_label() {
        build_message_widget(content_item);
    }

    private bool message_has_code_blocks(string body) {
        MatchInfo match_info;
        Util.get_code_block_regex().match(body, 0, out match_info);
        return match_info.matches();
    }

    private void build_message_widget(ContentItem item) {
        MessageItem message_item = item as MessageItem;
        Message message = message_item.message;
        string body = message.body;
        if (body == null) body = "";

        bool dark_theme = Util.is_dark_theme(this.label);

        if (!message_has_code_blocks(body)) {
            // Simple message: just use the label
            generate_markup_text(item, label);
            if (active_widget != label) {
                active_widget = label;
                if (outer != null) outer.set_widget(label, Plugins.WidgetType.GTK4, 2);
            }
            return;
        }

        // Message with code blocks: build composite widget
        if (content_box != null) {
            // Remove old children
            Widget? child = content_box.get_first_child();
            while (child != null) {
                Widget? next = child.get_next_sibling();
                content_box.remove(child);
                child = next;
            }
        } else {
            content_box = new Box(Orientation.VERTICAL, 6) { hexpand = true };
        }

        // Pre-process: get clean body (with fallback removal)
        var markups = new ArrayList<Xep.MessageMarkup.Span>();
        foreach (var markup in message.get_markups()) {
            markups.add(new Xep.MessageMarkup.Span() { types=markup.types, start_char=markup.start_char, end_char=markup.end_char });
        }
        string processed_body = body;
        if (processed_body.length > 10000) {
            processed_body = processed_body.substring(0, 10000) + " [" + _("Message too long") + "]";
        }
        processed_body = Util.remove_fallbacks_adjust_markups(processed_body, message.quoted_item_id > 0, message.get_fallbacks(), markups);

        Conversation conversation = message_item.conversation;
        bool theme_dependent = false;

        // Split by code blocks
        string remaining = processed_body;
        MatchInfo match_info;
        while (Util.get_code_block_regex().match(remaining, 0, out match_info) && match_info.matches()) {
            int start, end;
            match_info.fetch_pos(0, out start, out end);
            string lang = match_info.fetch(1) ?? "";
            string code_content = match_info.fetch(2) ?? "";

            // Text before code block
            string before = remaining[0:start];
            if (before.strip().length > 0) {
                var text_label = create_text_label();
                string before_markup = Util.unbreak_space_around_non_spacing_mark((owned) before);
                if (conversation.type_ == Conversation.Type.GROUPCHAT) {
                    before_markup = Util.parse_add_markup_theme(before_markup, conversation.nickname, true, true, true, dark_theme, ref theme_dependent);
                } else {
                    before_markup = Util.parse_add_markup_theme(before_markup, null, true, true, true, dark_theme, ref theme_dependent);
                }
                text_label.label = before_markup;
                content_box.append(text_label);
            }

            // Code block widget
            var code_widget = new CodeBlockWidget(code_content, lang, dark_theme);
            content_box.append(code_widget);

            remaining = remaining[end:remaining.length];
        }

        // Remaining text after last code block
        if (remaining.strip().length > 0) {
            var text_label = create_text_label();
            string after_markup = Util.unbreak_space_around_non_spacing_mark((owned) remaining);
            if (conversation.type_ == Conversation.Type.GROUPCHAT) {
                after_markup = Util.parse_add_markup_theme(after_markup, conversation.nickname, true, true, true, dark_theme, ref theme_dependent);
            } else {
                after_markup = Util.parse_add_markup_theme(after_markup, null, true, true, true, dark_theme, ref theme_dependent);
            }

            // Append status suffixes to last text label
            string dim_color = dark_theme ? "#BDBDBD" : "#707070";
            additional_info = AdditionalInfo.NONE;
            if (message.body == "") {
                after_markup = @"<i><span size='small' color='$dim_color'>%s</span></i>".printf(_("Message deleted"));
                theme_dependent = true;
            }
            if (message.edit_to != null) {
                after_markup += @"  <span size='small' color='$dim_color'>(%s)</span>".printf(_("edited"));
                theme_dependent = true;
            }
            if (message.direction == Message.DIRECTION_SENT && (message.marked == Message.Marked.SENDING || message.marked == Message.Marked.UNSENT)) {
                if (message.time.compare(new DateTime.now_utc().add_seconds(-10)) < 0) {
                    after_markup += @"  <span size='small' color='$dim_color'>%s</span>".printf(_("pending\u2026"));
                    theme_dependent = true;
                    additional_info = AdditionalInfo.PENDING;
                }
            } else if (message.direction == Message.DIRECTION_SENT && message.marked == Message.Marked.ERROR) {
                string error_color = Util.rgba_to_hex(Util.get_label_pango_color(text_label, "@error_color"));
                after_markup += "  <span size='small' color='%s'>%s</span>".printf(error_color, _("delivery failed"));
                theme_dependent = true;
                additional_info = AdditionalInfo.DELIVERY_FAILED;
            }

            text_label.label = after_markup;
            content_box.append(text_label);
        } else {
            // No trailing text but may need status - add tiny status label
            string dim_color = dark_theme ? "#BDBDBD" : "#707070";
            string status_markup = "";
            additional_info = AdditionalInfo.NONE;
            if (message.body == "") {
                status_markup = @"<i><span size='small' color='$dim_color'>%s</span></i>".printf(_("Message deleted"));
            }
            if (message.edit_to != null) {
                status_markup += @"  <span size='small' color='$dim_color'>(%s)</span>".printf(_("edited"));
            }
            if (message.direction == Message.DIRECTION_SENT && message.marked == Message.Marked.ERROR) {
                string error_color = "#CC0000";
                status_markup += "  <span size='small' color='%s'>%s</span>".printf(error_color, _("delivery failed"));
                additional_info = AdditionalInfo.DELIVERY_FAILED;
            }
            if (status_markup.length > 0) {
                var status_label = create_text_label();
                status_label.label = status_markup;
                content_box.append(status_label);
            }
        }

        if (theme_dependent && realize_id == -1) {
            realize_id = label.realize.connect(update_label);
        }

        active_widget = content_box;
        if (outer != null) outer.set_widget(content_box, Plugins.WidgetType.GTK4, 2);
    }

    private Label create_text_label() {
        var l = new Label("") {
            use_markup = true,
            xalign = 0,
            selectable = true,
            wrap = true,
            wrap_mode = Pango.WrapMode.WORD_CHAR,
            hexpand = true
        };
        l.activate_link.connect(on_label_activate_link);
        return l;
    }

    public override Object? get_widget(Plugins.ConversationItemWidgetInterface outer, Plugins.WidgetType type) {
        this.outer = outer;

        this.notify["in-edit-mode"].connect(on_in_edit_mode_changed);

        build_message_widget(content_item);
        // active_widget was set by build_message_widget

        if (message_item.message.quoted_item_id > 0) {
            var quoted_content_item = stream_interactor.get_module(ContentItemStore.IDENTITY).get_item_by_id(message_item.conversation, message_item.message.quoted_item_id);
            if (quoted_content_item != null) {
                var quote_model = new Quote.Model.from_content_item(quoted_content_item, message_item.conversation, stream_interactor);
                quote_model.jump_to.connect(() => {
                    GLib.Application.get_default().activate_action("jump-to-conversation-message", new GLib.Variant.tuple(new GLib.Variant[] { new GLib.Variant.int32(message_item.conversation.id), new GLib.Variant.int32(quoted_content_item.id) }));
                });
                var quote_widget = Quote.get_widget(quote_model);
                outer.set_widget(quote_widget, Plugins.WidgetType.GTK4, 1);
            }
        }
        return active_widget;
    }

    public override Gee.List<Plugins.MessageAction>? get_item_actions(Plugins.WidgetType type) {
        if (in_edit_mode) return null;

        Gee.List<Plugins.MessageAction> actions = new ArrayList<Plugins.MessageAction>();

        bool correction_allowed = stream_interactor.get_module(MessageCorrection.IDENTITY).is_own_correction_allowed(message_item.conversation, message_item.message);
        if (correction_allowed) {
            Plugins.MessageAction action1 = new Plugins.MessageAction();
            action1.name = "correction";
            action1.icon_name = "dino-document-edit-symbolic";
            action1.tooltip = _("Edit message");
            action1.shortcut_action = false;
            action1.callback = () => {
                this.in_edit_mode = true;
            };
            actions.add(action1);
        }

        actions.add(get_reply_action(content_item, message_item.conversation, stream_interactor));
        actions.add(get_reaction_action(content_item, message_item.conversation, stream_interactor));

        var delete_action = get_delete_action(content_item, message_item.conversation, stream_interactor);
        if (delete_action != null) actions.add(delete_action);

        return actions;
    }

    private void on_in_edit_mode_changed() {
        if (in_edit_mode == false) return;
        bool allowed = stream_interactor.get_module(MessageCorrection.IDENTITY).is_own_correction_allowed(message_item.conversation, message_item.message);
        if (allowed) {
            MessageItem message_item = content_item as MessageItem;
            Message message = message_item.message;

            edit_mode = new MessageItemEditMode();
            controller = new ChatTextViewController(edit_mode.chat_text_view, stream_interactor);
            Conversation conversation = message_item.conversation;
            controller.initialize_for_conversation(conversation);

            edit_mode.cancelled.connect(() => {
                in_edit_mode = false;
                build_message_widget(content_item);
            });
            edit_mode.send.connect(() => {
                string text = edit_mode.chat_text_view.text_view.buffer.text;
                var markups = edit_mode.chat_text_view.get_markups();
                Dino.send_message(message_item.conversation, text, message_item.message.quoted_item_id, message_item.message, markups);

                in_edit_mode = false;
                build_message_widget(content_item);
            });

            edit_mode.chat_text_view.set_text(message);

            outer.set_widget(edit_mode, Plugins.WidgetType.GTK4, 2);
            edit_mode.chat_text_view.text_view.grab_focus();
        } else {
            this.in_edit_mode = false;
        }
    }

    private void on_updated_item(ContentItem content_item) {
        if (this.content_item.id == content_item.id) {
            this.content_item = content_item;
            message_item = content_item as MessageItem;
            update_label();
        }
    }

    public static bool on_label_activate_link(string uri) {
        // Always handle xmpp URIs with Dino
        if (!uri.has_prefix("xmpp:")) return false;
        File file = File.new_for_uri(uri);
        Dino.Application.get_default().open(new File[]{file}, "");
        return true;
    }

    public override void dispose() {
        stream_interactor.get_module(MessageCorrection.IDENTITY).received_correction.disconnect(on_updated_item);
        stream_interactor.get_module(MessageDeletion.IDENTITY).item_deleted.disconnect(on_updated_item);
        this.notify["in-edit-mode"].disconnect(on_in_edit_mode_changed);
        if (marked_notify_handler_id != -1) {
            this.disconnect(marked_notify_handler_id);
        }
        if (realize_id != -1) {
            label.disconnect(realize_id);
        }
        if (pending_timeout_id != -1) {
            Source.remove(pending_timeout_id);
        }
        if (label != null) {
            label.unparent();
            label.dispose();
            label = null;
        }
        if (content_box != null) {
            content_box.unparent();
            content_box.dispose();
            content_box = null;
        }
        active_widget = null;
        base.dispose();
    }
}

[GtkTemplate (ui = "/im/dino/Dino/message_item_widget_edit_mode.ui")]
public class MessageItemEditMode : Box {

    public signal void cancelled();
    public signal void send();

    [GtkChild] public unowned MenuButton emoji_button;
    [GtkChild] public unowned ChatTextView chat_text_view;
    [GtkChild] public unowned Button cancel_button;
    [GtkChild] public unowned Button send_button;
    [GtkChild] public unowned Frame frame;

    construct {
        Util.force_css(frame, "* { border-radius: 3px; padding: 0px 7px; }");

        EmojiChooser chooser = new EmojiChooser();
        chooser.emoji_picked.connect((emoji) => {
            chat_text_view.text_view.buffer.insert_at_cursor(emoji, emoji.data.length);
        });
        emoji_button.set_popover(chooser);

        chat_text_view.text_view.buffer.changed.connect_after(on_text_view_changed);

        cancel_button.clicked.connect(() => cancelled());
        send_button.clicked.connect(() => send());
        chat_text_view.cancel_input.connect(() => cancelled());
        chat_text_view.send_text.connect(() => send());
    }

    private void on_text_view_changed() {
        send_button.sensitive = chat_text_view.text_view.buffer.text != "";
    }
}

}
