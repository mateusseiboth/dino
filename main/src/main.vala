using Dino.Entities;
using Dino.Ui;

extern const string GETTEXT_PACKAGE;
extern const string LOCALE_INSTALL_DIR;

namespace Dino {

void main(string[] args) {

    try{
        string? exec_path = args.length > 0 ? args[0] : null;
        SearchPathGenerator search_path_generator = new SearchPathGenerator(exec_path);
        string base_dir = Path.get_dirname(exec_path ?? ".");
        string share_dir = Path.build_filename(base_dir, "share");
        string etc_dir = Path.build_filename(base_dir, "etc");
        string schema_dir = Path.build_filename(share_dir, "glib-2.0", "schemas");

        // If this looks like the Windows portable bundle, configure runtime paths.
        bool is_windows_bundle = FileUtils.test(Path.build_filename(base_dir, "libgtk-4-1.dll"), FileTest.IS_REGULAR);
        string? log_file = Environment.get_variable("DINO_LOG_FILE");
        if (log_file == null && is_windows_bundle) {
            log_file = Path.build_filename(base_dir, "dino.log");
        }
        if (log_file != null) {
            install_file_logger(log_file);
        }
        if (is_windows_bundle) {
            string pixbuf_dir = Path.build_filename(base_dir, "lib", "gdk-pixbuf-2.0", "2.10.0", "loaders");
            string pixbuf_cache = Path.build_filename(base_dir, "lib", "gdk-pixbuf-2.0", "2.10.0", "loaders.cache");
            string fontconfig_file = Path.build_filename(etc_dir, "fonts", "fonts.conf");
            string bundle_fontconfig_file = Path.build_filename(etc_dir, "fonts", "dino-fonts.conf");
            string path = Environment.get_variable("PATH") ?? "";

            Environment.set_variable("PATH", base_dir + ";" + path, true);

            if (Environment.get_variable("XDG_DATA_DIRS") == null && FileUtils.test(share_dir, FileTest.IS_DIR)) {
                Environment.set_variable("XDG_DATA_DIRS", share_dir, false);
            }
            if (Environment.get_variable("XDG_DATA_HOME") == null && FileUtils.test(share_dir, FileTest.IS_DIR)) {
                Environment.set_variable("XDG_DATA_HOME", share_dir, false);
            }
            if (Environment.get_variable("GDK_PIXBUF_MODULEDIR") == null && FileUtils.test(pixbuf_dir, FileTest.IS_DIR)) {
                Environment.set_variable("GDK_PIXBUF_MODULEDIR", pixbuf_dir, false);
            }
            if (Environment.get_variable("GDK_PIXBUF_MODULE_FILE") == null && FileUtils.test(pixbuf_cache, FileTest.IS_REGULAR)) {
                Environment.set_variable("GDK_PIXBUF_MODULE_FILE", pixbuf_cache, false);
            }
            if (Environment.get_variable("FONTCONFIG_FILE") == null) {
                if (FileUtils.test(bundle_fontconfig_file, FileTest.IS_REGULAR)) {
                    Environment.set_variable("FONTCONFIG_FILE", bundle_fontconfig_file, false);
                } else if (FileUtils.test(fontconfig_file, FileTest.IS_REGULAR)) {
                    Environment.set_variable("FONTCONFIG_FILE", fontconfig_file, false);
                }
            }
            if (Environment.get_variable("GSK_RENDERER") == null) {
                Environment.set_variable("GSK_RENDERER", "cairo", false);
            }
            if (Environment.get_variable("PANGOCAIRO_BACKEND") == null) {
                Environment.set_variable("PANGOCAIRO_BACKEND", "fontconfig", false);
            }
        }

        Intl.textdomain(GETTEXT_PACKAGE);
        internationalize(GETTEXT_PACKAGE, search_path_generator.get_locale_path(GETTEXT_PACKAGE, LOCALE_INSTALL_DIR));

        if (Environment.get_variable("GSETTINGS_SCHEMA_DIR") == null &&
                FileUtils.test(Path.build_filename(schema_dir, "gschema.compiled"), FileTest.IS_REGULAR)) {
            Environment.set_variable("GSETTINGS_SCHEMA_DIR", schema_dir, false);
        }

        Gtk.init();

        // Ensure custom widgets referenced by GtkBuilder templates are registered.
        Type[] builder_types = {
            typeof(Dino.Ui.NaturalSizeIncrease),
            typeof(Dino.Ui.SizeRequestBox),
            typeof(Dino.Ui.SizeRequestBin),
            typeof(Dino.Ui.SizingBin),
            typeof(Dino.Ui.AvatarPicture),
            typeof(Dino.Ui.ChatTextView),
            typeof(Dino.Ui.ChatInput.View),
            typeof(Dino.Ui.ConversationSummary.ConversationView),
            typeof(Dino.Ui.ConversationView),
            typeof(Dino.Ui.ConversationSelector),
            typeof(Dino.Ui.AccountComboBox),
            typeof(Dino.Ui.ViewModel.ConversationDetails),
            typeof(Dino.Ui.ViewModel.PreferencesDialog),
            typeof(Dino.Ui.PreferencesWindowAccounts),
            typeof(Dino.Ui.PreferencesWindowEncryption),
            typeof(Dino.Ui.GeneralPreferencesPage),
        };
        foreach (Type t in builder_types) {
            t.class_ref();
        }
        Dino.Ui.Application app = new Dino.Ui.Application() { search_path_generator=search_path_generator };
        Plugins.Loader loader = new Plugins.Loader(app);
        loader.load_all();

        app.run(args);
        loader.shutdown();
    } catch (Error e) {
        warning(@"Fatal error: $(e.message)");
    }
}

private void install_file_logger(string log_path) {
    FileStream? log_stream = FileStream.open(log_path, "a");
    if (log_stream == null) {
        return;
    }

    write_log_line(log_stream, "Logger initialized");

    LogLevelFlags flags = LogLevelFlags.LEVEL_MASK | LogLevelFlags.FLAG_FATAL | LogLevelFlags.FLAG_RECURSION;
    Log.set_handler(null, flags, (domain, level, message) => {
        string level_str = level.to_string();
        string ts = new DateTime.now_local().format("%Y-%m-%d %H:%M:%S");
        if (domain != null && domain != "") {
            log_stream.printf("%s [%s] %s: %s\n", ts, level_str, domain, message);
        } else {
            log_stream.printf("%s [%s] %s\n", ts, level_str, message);
        }
        log_stream.flush();
    });
}

private void write_log_line(FileStream log_stream, string message) {
    string ts = new DateTime.now_local().format("%Y-%m-%d %H:%M:%S");
    log_stream.printf("%s [INFO] %s\n", ts, message);
    log_stream.flush();
}

}
