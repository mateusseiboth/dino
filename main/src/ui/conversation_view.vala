using Gee;
using Gdk;
using Gtk;

using Dino.Entities;

namespace Dino.Ui {

[GtkTemplate (ui = "/im/dino/Dino/conversation_view.ui")]
public class ConversationView : Widget {

    [GtkChild] public unowned Revealer goto_end_revealer;
    [GtkChild] public unowned Button goto_end_button;
    [GtkChild] public unowned ChatInput.View chat_input;
    [GtkChild] public unowned ConversationSummary.ConversationView conversation_frame;
    [GtkChild] public unowned Overlay conversation_overlay;

    public EffectsOverlay effects_overlay = new EffectsOverlay();

    construct {
        this.layout_manager = new BinLayout();
    }

    public void init_effects() {
        conversation_overlay.add_overlay(effects_overlay);
    }
}

}
