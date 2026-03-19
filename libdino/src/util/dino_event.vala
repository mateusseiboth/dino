namespace Dino {

public class DinoEvent : Object {
    public const string EVENT_PREFIX = "dinoevt:v2:";

    public enum EventType {
        PARTY,
        SPACE,
        ATTENTION,
        UNKNOWN;

        public string to_string() {
            switch (this) {
                case PARTY: return "party";
                case SPACE: return "space";
                case ATTENTION: return "attention";
                default: return "unknown";
            }
        }

        public static EventType from_string(string s) {
            switch (s) {
                case "party": return PARTY;
                case "space": return SPACE;
                case "attention": return ATTENTION;
                default: return UNKNOWN;
            }
        }
    }

    public static bool is_event_message(string? text) {
        if (text == null) return false;
        return text.has_prefix(EVENT_PREFIX);
    }

    public static string encode_event(EventType event_type) {
        return EVENT_PREFIX + event_type.to_string();
    }

    public static EventType decode_event(string text) {
        if (!is_event_message(text)) return EventType.UNKNOWN;
        string event_name = text.substring(EVENT_PREFIX.length).strip();
        return EventType.from_string(event_name);
    }
}

}
