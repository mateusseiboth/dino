using Gee;
using Gdk;
using Gtk;
using Xmpp;
using Dino.Entities;

namespace Dino.Ui {

/**
 * MetaItem for sticker messages – rendered as a rounded image rather than a
 * text bubble.  A sticker message body has the form:
 *   dinosticker:v1:<sha256>:<download_url>
 */
public class StickerMetaItem : ConversationSummary.ContentMetaItem {

    private StreamInteractor stream_interactor;
    private MessageItem message_item;

    public StickerMetaItem(ContentItem content_item, StreamInteractor stream_interactor) {
        base(content_item);
        this.stream_interactor = stream_interactor;
        this.message_item = content_item as MessageItem;

        // Keep same bubble/avatar grouping as messages
        this.can_merge       = true;
        this.requires_avatar = true;
        this.requires_header = true;
    }

    public override Object? get_widget(Plugins.ConversationItemWidgetInterface outer,
                                       Plugins.WidgetType type) {
        return new StickerWidget(message_item.message, stream_interactor);
    }

    public override Gee.List<Plugins.MessageAction>? get_item_actions(Plugins.WidgetType type) {
        var actions = new ArrayList<Plugins.MessageAction>();
        actions.add(get_reaction_action(content_item, message_item.conversation, stream_interactor));

        // Received stickers: offer "Save to my stickers"
        if (message_item.message.direction == Entities.Message.DIRECTION_RECEIVED) {
            var save_action = new Plugins.MessageAction();
            save_action.name       = "save_sticker";
            save_action.icon_name  = "bookmark-new-symbolic";
            save_action.tooltip    = _("Save as sticker");
            save_action.shortcut_action = false;
            save_action.callback = (_variant) => {
                StickerManager mgr = stream_interactor.get_module(StickerManager.IDENTITY);
                if (StickerMessage.is_base64_sticker(message_item.message.body)) {
                    mgr.ensure_cached_base64(message_item.message.body);
                }
                // Legacy URL-based stickers cannot be saved without network access
            };
            actions.add(save_action);
        }

        return actions;
    }
}

// ---------------------------------------------------------------------------

/**
 * Widget that shows a sticker in the conversation view.
 * It looks up the image from disk; if not present, downloads it asynchronously.
 */
public class StickerWidget : SizeRequestBin {

    private const int MAX_SIZE = 200;

    private Gtk.Picture picture;
    private Gtk.Spinner spinner;
    private Gtk.Stack stack;

    private Entities.Message message;
    private StreamInteractor stream_interactor;

    public StickerWidget(Entities.Message message, StreamInteractor stream_interactor) {
        this.message = message;
        this.stream_interactor = stream_interactor;

        this.halign = Gtk.Align.START;
        this.add_css_class("sticker-widget");

        stack = new Gtk.Stack();
        stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
        stack.insert_after(this, null);

        spinner = new Gtk.Spinner() { spinning = true };
        spinner.width_request  = MAX_SIZE;
        spinner.height_request = MAX_SIZE;
        stack.add_named(spinner, "loading");

        picture = new Gtk.Picture();
        picture.content_fit   = Gtk.ContentFit.CONTAIN;
        picture.can_shrink    = true;
        picture.width_request  = MAX_SIZE;
        picture.height_request = MAX_SIZE;
        stack.add_named(picture, "image");

        stack.visible_child_name = "loading";

        load_sticker();
    }

    private void load_sticker() {
        StickerManager mgr = stream_interactor.get_module(StickerManager.IDENTITY);

        // Inline base64 sticker
        if (StickerMessage.is_base64_sticker(message.body)) {
            StickerEntry? entry = mgr.ensure_cached_base64(message.body);
            if (entry != null && FileUtils.test(entry.path, FileTest.EXISTS)) {
                display_from_path(entry.path);
            } else {
                show_broken();
            }
            return;
        }

        // Legacy URL-based sticker
        string hash, url;
        if (!StickerMessage.decode(message.body, out hash, out url)) {
            show_broken();
            return;
        }
        StickerEntry? entry = mgr.get_by_hash(hash);
        if (entry != null && FileUtils.test(entry.path, FileTest.EXISTS)) {
            display_from_path(entry.path);
        } else {
            show_broken();
        }
    }

    private void display_from_path(string path) {
        try {
            picture.set_filename(path);
            stack.visible_child_name = "image";
        } catch (Error e) {
            warning("StickerWidget: could not load %s: %s", path, e.message);
            show_broken();
        }
    }

    private void show_broken() {
        spinner.spinning = false;
        var icon = new Gtk.Image.from_icon_name("image-missing-symbolic");
        icon.pixel_size = 48;
        icon.width_request  = MAX_SIZE;
        icon.height_request = MAX_SIZE;
        stack.add_named(icon, "broken");
        stack.visible_child_name = "broken";
    }
}

}
