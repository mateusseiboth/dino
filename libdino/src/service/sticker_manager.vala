using Gee;
using Xmpp;
using Dino.Entities;

namespace Dino {

/**
 * Lightweight value object for a sticker stored on disk.
 */
public class StickerEntry : Object {
    public int id { get; set; default = -1; }
    public string hash { get; set; }
    public string path { get; set; }
    public string? name { get; set; }
    public string? mime_type { get; set; }
    public long file_size { get; set; default = 0; }
    public string? cached_url { get; set; }
}

/**
 * Helpers to encode / decode sticker message bodies.
 *
 * Wire formats:
 *   dinosticker:v1:<sha256hex>:<download_url>         (URL-based, legacy)
 *   dinosticker:v1:base64:<mime_type>:<base64data>    (inline base64)
 */
public class StickerMessage : Object {
    public const string STICKER_PREFIX   = "dinosticker:v1:";
    public const string BASE64_SUBPREFIX = "base64:";

    public static bool is_sticker_message(string? text) {
        if (text == null) return false;
        return text.has_prefix(STICKER_PREFIX);
    }

    /** Encode URL-based sticker. */
    public static string encode(string hash, string url) {
        return STICKER_PREFIX + hash + ":" + url;
    }

    /** Encode inline base64 sticker. */
    public static string encode_base64(string mime_type, uint8[] data) {
        string b64 = Base64.encode(data);
        return STICKER_PREFIX + BASE64_SUBPREFIX + mime_type + ":" + b64;
    }

    /** Returns true if this is an inline base64 sticker. */
    public static bool is_base64_sticker(string text) {
        if (!is_sticker_message(text)) return false;
        string rest = text.substring(STICKER_PREFIX.length);
        return rest.has_prefix(BASE64_SUBPREFIX);
    }

    /**
     * Decode a base64 sticker message.
     * Returns false if not a valid base64 sticker.
     */
    public static bool decode_base64(string text, out string mime_type, out uint8[]? data) {
        mime_type = "image/png";
        data = null;
        if (!is_base64_sticker(text)) return false;
        string rest = text.substring(STICKER_PREFIX.length + BASE64_SUBPREFIX.length);
        int colon = rest.index_of(":");
        if (colon < 0) return false;
        mime_type = rest.substring(0, colon);
        string b64 = rest.substring(colon + 1);
        data = Base64.decode(b64);
        return data != null && data.length > 0;
    }

    /** Decode a URL-based sticker. Returns false if body could not be parsed. */
    public static bool decode(string text, out string hash, out string url) {
        hash = "";
        url = "";
        if (!is_sticker_message(text)) return false;
        if (is_base64_sticker(text)) return false;
        string rest = text.substring(STICKER_PREFIX.length);
        int colon_pos = rest.index_of(":");
        if (colon_pos < 0) return false;
        hash = rest.substring(0, colon_pos);
        url  = rest.substring(colon_pos + 1);
        return hash.length > 0 && url.length > 0;
    }
}

/**
 * Manages the local sticker library and handles send/receive of sticker messages.
 * Stickers are transmitted inline as base64 — no server upload required.
 */
public class StickerManager : StreamInteractionModule, Object {
    public static ModuleIdentity<StickerManager> IDENTITY = new ModuleIdentity<StickerManager>("sticker_manager");
    public string id { get { return IDENTITY.id; } }

    private StreamInteractor stream_interactor;
    private Database db;

    public static void start(StreamInteractor stream_interactor, Database db) {
        StickerManager m = new StickerManager(stream_interactor, db);
        stream_interactor.add_module(m);
    }

    public static string get_sticker_dir() {
        return Path.build_filename(Dino.get_storage_dir(), "stickers");
    }

    private StickerManager(StreamInteractor stream_interactor, Database db) {
        this.stream_interactor = stream_interactor;
        this.db = db;
        DirUtils.create_with_parents(get_sticker_dir(), 0700);
    }

    // -------------------------------------------------------------------------
    // Local library
    // -------------------------------------------------------------------------

    public Gee.List<StickerEntry> get_all_stickers() {
        var list = new ArrayList<StickerEntry>();
        foreach (var row in db.sticker.select()) {
            list.add(row_to_entry(row));
        }
        return list;
    }

    public StickerEntry? get_by_hash(string hash) {
        var row_opt = db.sticker.select()
            .with(db.sticker.hash, "=", hash)
            .single().row();
        if (row_opt.is_present()) return row_to_entry(row_opt.inner);
        return null;
    }

    /**
     * Hash the given file, copy it into the sticker directory, and persist an
     * entry in the database.  Returns null on failure.
     */
    public StickerEntry? add_sticker_from_file(File file) {
        try {
            string hash = compute_file_hash(file);

            StickerEntry? existing = get_by_hash(hash);
            if (existing != null) return existing;

            string? mime_type = null;
            try {
                var fi = file.query_info("standard::content-type", FileQueryInfoFlags.NONE);
                mime_type = fi.get_content_type();
            } catch (Error e) {}

            string ext = get_extension_for_mime(mime_type, file.get_basename());
            string dest_path = Path.build_filename(get_sticker_dir(), hash + ext);
            file.copy(File.new_for_path(dest_path), FileCopyFlags.OVERWRITE);

            long size = 0;
            try {
                var fi2 = File.new_for_path(dest_path).query_info("standard::size", FileQueryInfoFlags.NONE);
                size = (long) fi2.get_size();
            } catch (Error e) {}

            string? orig_name = file.get_basename();

            var entry = new StickerEntry();
            entry.hash      = hash;
            entry.path      = dest_path;
            entry.name      = orig_name;
            entry.mime_type = mime_type;
            entry.file_size = size;

            var ins = db.sticker.insert()
                .value(db.sticker.hash, hash)
                .value(db.sticker.path, dest_path)
                .value(db.sticker.name, orig_name ?? "sticker")
                .value(db.sticker.file_size, size);
            if (mime_type != null) ins = ins.value(db.sticker.mime_type, mime_type);
            else ins = ins.value_null(db.sticker.mime_type);
            entry.id = (int) ins.perform();

            return entry;
        } catch (Error e) {
            warning("StickerManager.add_sticker_from_file: %s", e.message);
            return null;
        }
    }

    public void remove_sticker(StickerEntry sticker) {
        db.sticker.delete().with(db.sticker.id, "=", sticker.id).perform();
        try { File.new_for_path(sticker.path).delete(); } catch (Error e) {}
    }

    // -------------------------------------------------------------------------
    // Sending — inline base64, no server upload required
    // -------------------------------------------------------------------------

    public void send_sticker(Conversation conversation, StickerEntry sticker) {
        try {
            uint8[] data = File.new_for_path(sticker.path).load_bytes().get_data();
            string mime = sticker.mime_type ?? "image/png";
            string body = StickerMessage.encode_base64(mime, data);
            Dino.send_message(conversation, body, 0, null,
                new ArrayList<Xmpp.Xep.MessageMarkup.Span>());
        } catch (Error e) {
            warning("StickerManager.send_sticker: %s", e.message);
            Dino.send_message(conversation,
                "⚠ Could not send sticker: %s".printf(e.message),
                0, null, new ArrayList<Xmpp.Xep.MessageMarkup.Span>());
        }
    }

    // -------------------------------------------------------------------------
    // Receiving / caching
    // -------------------------------------------------------------------------

    /**
     * Decode an inline base64 sticker, write to disk and register in the DB.
     * Returns null if the message is not a valid base64 sticker.
     */
    public StickerEntry? ensure_cached_base64(string message_body) {
        string mime_type;
        uint8[]? data;
        if (!StickerMessage.decode_base64(message_body, out mime_type, out data)) return null;

        var checksum = new Checksum(ChecksumType.SHA256);
        checksum.update(data, data.length);
        string hash = checksum.get_string();

        StickerEntry? existing = get_by_hash(hash);
        if (existing != null && FileUtils.test(existing.path, FileTest.EXISTS)) {
            return existing;
        }

        string ext = get_extension_for_mime(mime_type, "sticker");
        string dest_path = Path.build_filename(get_sticker_dir(), hash + ext);

        try {
            File.new_for_path(dest_path).replace_contents(data, null, false,
                FileCreateFlags.REPLACE_DESTINATION, null);
        } catch (Error e) {
            warning("StickerManager.ensure_cached_base64: write failed: %s", e.message);
            return null;
        }

        return register_downloaded(hash, dest_path, mime_type, null, data.length);
    }

    private StickerEntry register_downloaded(string hash, string path,
                                             string? mime_type, string? url,
                                             long size = 0) {
        var entry = new StickerEntry();
        entry.hash       = hash;
        entry.path       = path;
        entry.mime_type  = mime_type;
        entry.cached_url = url;
        entry.file_size  = size;
        entry.name       = Path.get_basename(path);

        var ins = db.sticker.insert()
            .value(db.sticker.hash, hash)
            .value(db.sticker.path, path)
            .value(db.sticker.name, entry.name)
            .value(db.sticker.file_size, size);
        if (mime_type != null) ins = ins.value(db.sticker.mime_type, mime_type);
        else ins = ins.value_null(db.sticker.mime_type);
        if (url != null) ins = ins.value(db.sticker.cached_url, url);
        else ins = ins.value_null(db.sticker.cached_url);
        entry.id = (int) ins.perform();

        return entry;
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private string compute_file_hash(File file) throws Error {
        var checksum = new Checksum(ChecksumType.SHA256);
        FileInputStream stream = file.read();
        uint8[] buf = new uint8[65536];
        ssize_t n;
        while ((n = stream.read(buf)) > 0) {
            checksum.update(buf, n);
        }
        stream.close();
        return checksum.get_string();
    }

    private string get_extension_for_mime(string? mime, string fallback) {
        if (mime != null) {
            switch (mime.split(";")[0].strip().ascii_down()) {
                case "image/png":     return ".png";
                case "image/jpeg":    return ".jpg";
                case "image/gif":     return ".gif";
                case "image/webp":    return ".webp";
                case "image/svg+xml": return ".svg";
            }
        }
        string base_name = Path.get_basename(fallback);
        int dot = base_name.last_index_of(".");
        if (dot >= 0) return base_name.substring(dot);
        return ".bin";
    }

    private StickerEntry row_to_entry(Qlite.Row row) {
        var e = new StickerEntry();
        e.id         = row[db.sticker.id];
        e.hash       = row[db.sticker.hash];
        e.path       = row[db.sticker.path];
        e.name       = row[db.sticker.name];
        e.mime_type  = row[db.sticker.mime_type];
        e.file_size  = (long) row[db.sticker.file_size];
        e.cached_url = row[db.sticker.cached_url];
        return e;
    }
}

}
