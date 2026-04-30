using Gee;
using Gtk;
using Dino.Entities;

namespace Dino.Ui.ChatInput {

/**
 * Popover that lets the user browse and send their local sticker library,
 * as well as add new stickers from disk.
 */
public class StickerPicker : Gtk.Popover {

    public signal void sticker_selected(StickerEntry sticker);

    private StreamInteractor stream_interactor;
    private StickerManager sticker_manager;
    private Gtk.FlowBox flow_box;

    public StickerPicker(StreamInteractor stream_interactor) {
        Object();
        this.stream_interactor = stream_interactor;
        this.sticker_manager = stream_interactor.get_module(StickerManager.IDENTITY);

        var vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
        vbox.margin_top    = 6;
        vbox.margin_bottom = 6;
        vbox.margin_start  = 6;
        vbox.margin_end    = 6;

        // Scrollable sticker grid
        var scroll = new Gtk.ScrolledWindow();
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scroll.width_request  = 316;
        scroll.height_request = 260;

        flow_box = new Gtk.FlowBox();
        flow_box.max_children_per_line = 4;
        flow_box.min_children_per_line = 4;
        flow_box.selection_mode = Gtk.SelectionMode.NONE;
        flow_box.homogeneous = true;
        flow_box.row_spacing = 4;
        flow_box.column_spacing = 4;
        scroll.set_child(flow_box);
        vbox.append(scroll);

        // Separator
        vbox.append(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));

        // "Add sticker" button at the bottom
        var add_btn = new Gtk.Button();
        add_btn.icon_name = "list-add-symbolic";
        add_btn.label = _("Add sticker...");
        add_btn.add_css_class("flat");
        add_btn.halign = Gtk.Align.CENTER;
        add_btn.clicked.connect(on_add_clicked);
        vbox.append(add_btn);

        set_child(vbox);

        // Populate from DB each time the popover opens
        this.show.connect(refresh_stickers);
    }

    // -------------------------------------------------------------------------

    private void refresh_stickers() {
        // Remove previous widgets
        Gtk.Widget? child = flow_box.get_first_child();
        while (child != null) {
            var next = child.get_next_sibling();
            flow_box.remove(child);
            child = next;
        }

        var stickers = sticker_manager.get_all_stickers();
        foreach (var sticker in stickers) {
            append_sticker_button(sticker);
        }

        if (stickers.is_empty) {
            var hint = new Gtk.Label(_("No stickers yet. Click \"Add sticker...\" to add one."));
            hint.use_markup = false;
            hint.wrap = true;
            hint.justify = Gtk.Justification.CENTER;
            hint.halign = Gtk.Align.CENTER;
            flow_box.append(hint);
        }
    }

    private void append_sticker_button(StickerEntry sticker) {
        var picture = new Gtk.Picture.for_filename(sticker.path);
        picture.content_fit = Gtk.ContentFit.CONTAIN;
        picture.width_request  = 64;
        picture.height_request = 64;
        picture.can_shrink = true;
        picture.hexpand = false;
        picture.vexpand = false;

        // Delete overlay
        var overlay = new Gtk.Overlay();
        overlay.set_child(picture);

        var del_btn = new Gtk.Button();
        del_btn.icon_name = "window-close-symbolic";
        del_btn.add_css_class("circular");
        del_btn.add_css_class("sticker-delete-btn");
        del_btn.halign = Gtk.Align.END;
        del_btn.valign = Gtk.Align.START;
        del_btn.tooltip_text = _("Remove sticker");
        del_btn.visible = false;
        overlay.add_overlay(del_btn);

        var btn = new Gtk.Button();
        btn.child = overlay;
        btn.add_css_class("flat");
        btn.add_css_class("sticker-thumb-btn");
        btn.tooltip_text = sticker.name ?? sticker.hash.substring(0, 8);
        btn.width_request  = 72;
        btn.height_request = 72;
        btn.hexpand = false;
        btn.vexpand = false;

        // Send sticker on left click
        btn.clicked.connect(() => {
            sticker_selected(sticker);
            popdown();
        });

        // Show/hide delete button on hover
        var motion = new Gtk.EventControllerMotion();
        motion.enter.connect((c, x, y) => { del_btn.visible = true; });
        motion.leave.connect((c) => { del_btn.visible = false; });
        btn.add_controller(motion);

        // Delete sticker on delete-button click
        del_btn.clicked.connect(() => {
            sticker_manager.remove_sticker(sticker);
            flow_box.remove(btn.get_parent() as Gtk.Widget ?? btn);
            // Full refresh to also remove the button wrapper
            refresh_stickers();
        });

        flow_box.append(btn);
    }

    private void on_add_clicked() {
        var chooser = new Gtk.FileChooserNative(
            _("Select sticker image"),
            get_root() as Gtk.Window,
            Gtk.FileChooserAction.OPEN,
            _("Add"),
            _("Cancel"));

        var filter = new Gtk.FileFilter();
        filter.name = _("Image files");
        filter.add_mime_type("image/png");
        filter.add_mime_type("image/jpeg");
        filter.add_mime_type("image/gif");
        filter.add_mime_type("image/webp");
        chooser.add_filter(filter);

        chooser.response.connect((response) => {
            if (response == Gtk.ResponseType.ACCEPT) {
                var file = chooser.get_file();
                if (file != null) {
                    StickerEntry? entry = sticker_manager.add_sticker_from_file(file);
                    if (entry != null) {
                        refresh_stickers();
                    }
                }
            }
        });
        chooser.show();
    }
}

}
