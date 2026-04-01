using Gee;
using Xmpp;
using Dino.Entities;

namespace Dino {

public class VacationNotice : StreamInteractionModule, Object {
    public static ModuleIdentity<VacationNotice> IDENTITY = new ModuleIdentity<VacationNotice>("vacation_notice");
    public string id { get { return IDENTITY.id; } }

    private StreamInteractor stream_interactor;
    private Database db;
    // Track JIDs already replied per account (key -> last_replied_time) within this session
    private HashMap<string, int64?> replied_times = new HashMap<string, int64?>();

    public static void start(StreamInteractor stream_interactor, Database db) {
        VacationNotice m = new VacationNotice(stream_interactor, db);
        stream_interactor.add_module(m);
    }

    private VacationNotice(StreamInteractor stream_interactor, Database db) {
        this.stream_interactor = stream_interactor;
        this.db = db;

        stream_interactor.get_module(MessageProcessor.IDENTITY).message_received.connect(on_message_received);
    }

    private void on_message_received(Entities.Message message, Conversation conversation) {
        debug("VacationNotice: message_received fired, type=%d dir_received=%s body=%s",
              (int)conversation.type_, message.direction.to_string(), message.body ?? "(null)");

        // Only reply to direct (chat) messages, not group chats
        if (conversation.type_ != Conversation.Type.CHAT) {
            debug("VacationNotice: skipping — not a CHAT conversation (type=%d)", (int)conversation.type_);
            return;
        }
        // Only to incoming messages with a body
        if (message.direction != Entities.Message.DIRECTION_RECEIVED) {
            debug("VacationNotice: skipping — not DIRECTION_RECEIVED");
            return;
        }
        if (message.body == null || message.body.strip() == "") {
            debug("VacationNotice: skipping — empty body");
            return;
        }

        Dino.Entities.Settings settings = Application.get_default().settings;
        debug("VacationNotice: enabled=%s message='%s'",
              settings.vacation_notice_enabled.to_string(), settings.vacation_notice_message);

        if (!settings.vacation_notice_enabled) return;

        string notice_text = settings.vacation_notice_message;
        if (notice_text == null || notice_text.strip() == "") {
            debug("VacationNotice: skipping — notice message is empty");
            return;
        }

        // Cooldown: reply at most once per JID per hour (3600 seconds)
        string reply_key = "%d|%s".printf(conversation.account.id, message.counterpart.bare_jid.to_string());
        int64 now = new DateTime.now_utc().to_unix();
        if (replied_times.has_key(reply_key)) {
            int64 last = replied_times[reply_key] ?? 0;
            if (now - last < 3600) {
                debug("VacationNotice: skipping — cooldown active (%llds ago)", now - last);
                return;
            }
        }
        replied_times[reply_key] = now;

        debug("VacationNotice: sending reply to %s", message.counterpart.to_string());

        // Use the same send pipeline as regular messages (handles encryption, content store, UI)
        Dino.send_message(conversation, notice_text, 0, null, new ArrayList<Xep.MessageMarkup.Span>());
    }
}

}
