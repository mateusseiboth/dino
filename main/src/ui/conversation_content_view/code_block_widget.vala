using Gtk;
using Gdk;
using Pango;
using Gee;

namespace Dino.Ui.ConversationSummary {

public class CodeBlockWidget : Box {

    private string code_text;
    private string language;
    private Button copy_button;
    private Revealer copy_revealer;

    public CodeBlockWidget(string code, string lang, bool dark_theme) {
        Object(orientation: Orientation.VERTICAL, spacing: 0);

        this.code_text = code;
        this.language = lang;

        add_css_class("code-block-container");

        // Header bar with language label and copy button
        var header = new Box(Orientation.HORIZONTAL, 0);
        header.add_css_class("code-block-header");

        if (lang.length > 0) {
            var lang_label = new Label(lang) { xalign = 0, hexpand = true };
            lang_label.add_css_class("code-block-lang");
            header.append(lang_label);
        } else {
            var spacer = new Box(Orientation.HORIZONTAL, 0) { hexpand = true };
            header.append(spacer);
        }

        copy_button = new Button();
        copy_button.icon_name = "dino-edit-copy-symbolic";
        copy_button.tooltip_text = _("Copy code");
        copy_button.add_css_class("flat");
        copy_button.add_css_class("code-block-copy");
        copy_button.clicked.connect(on_copy_clicked);

        copy_revealer = new Revealer();
        copy_revealer.transition_type = RevealerTransitionType.CROSSFADE;
        copy_revealer.transition_duration = 150;
        copy_revealer.reveal_child = false;
        copy_revealer.child = copy_button;
        header.append(copy_revealer);

        this.append(header);

        // Code content with syntax highlighting
        var code_label = new Label("") {
            use_markup = true,
            xalign = 0,
            selectable = true,
            wrap = true,
            wrap_mode = Pango.WrapMode.WORD_CHAR
        };
        code_label.add_css_class("code-block-content");

        string highlighted = apply_syntax_highlighting(code, lang, dark_theme);
        code_label.label = "<tt>" + highlighted + "</tt>";

        var code_scroll = new Box(Orientation.VERTICAL, 0);
        code_scroll.add_css_class("code-block-code");
        code_scroll.append(code_label);
        this.append(code_scroll);

        // Hover detection for copy button
        var motion = new EventControllerMotion();
        motion.enter.connect(() => {
            copy_revealer.reveal_child = true;
        });
        motion.leave.connect(() => {
            copy_revealer.reveal_child = false;
        });
        this.add_controller(motion);
    }

    private void on_copy_clicked() {
        var clipboard = this.get_clipboard();
        clipboard.set_text(code_text);

        // Visual feedback: change icon briefly
        copy_button.icon_name = "dino-double-tick-symbolic";
        copy_button.sensitive = false;
        Timeout.add(1500, () => {
            if (copy_button != null) {
                copy_button.icon_name = "dino-edit-copy-symbolic";
                copy_button.sensitive = true;
            }
            return false;
        });
    }

    private static string apply_syntax_highlighting(string code, string lang, bool dark_theme) {
        string escaped = Markup.escape_text(code);
        // Remove trailing newline for display
        if (escaped.has_suffix("\n")) {
            escaped = escaped.substring(0, escaped.length - 1);
        }

        if (lang.length == 0) {
            return escaped;
        }

        // Theme colors
        string c_keyword, c_string, c_comment, c_number, c_function, c_type, c_operator;
        if (dark_theme) {
            c_keyword  = "#C586C0";  // purple-pink
            c_string   = "#CE9178";  // orange
            c_comment  = "#6A9955";  // green
            c_number   = "#B5CEA8";  // light green
            c_function = "#DCDCAA";  // yellow
            c_type     = "#4EC9B0";  // teal
            c_operator = "#569CD6";  // blue
        } else {
            c_keyword  = "#AF00DB";
            c_string   = "#A31515";
            c_comment  = "#008000";
            c_number   = "#098658";
            c_function = "#795E26";
            c_type     = "#267F99";
            c_operator = "#0000FF";
        }

        string norm = lang.down();

        string[] keywords = {};
        string[] types = {};
        string line_comment = "//";
        string block_comment_start = "/*";
        string block_comment_end = "*/";
        bool hash_comments = false;

        if (norm == "js" || norm == "javascript" || norm == "ts" || norm == "typescript") {
            keywords = {"abstract", "async", "await", "break", "case", "catch", "class", "const",
                        "continue", "debugger", "default", "delete", "do", "else", "enum", "export",
                        "extends", "finally", "for", "from", "function", "if", "implements", "import",
                        "in", "instanceof", "interface", "let", "new", "of", "package", "private",
                        "protected", "public", "return", "static", "super", "switch", "this", "throw",
                        "try", "typeof", "var", "void", "while", "with", "yield",
                        "true", "false", "null", "undefined", "NaN", "Infinity"};
            types = {"string", "number", "boolean", "any", "never", "unknown", "object", "symbol",
                     "Array", "Map", "Set", "Promise", "Date", "RegExp", "Error", "Function",
                     "Object", "String", "Number", "Boolean", "Symbol"};
        } else if (norm == "python" || norm == "py") {
            keywords = {"and", "as", "assert", "async", "await", "break", "class", "continue",
                        "def", "del", "elif", "else", "except", "finally", "for", "from",
                        "global", "if", "import", "in", "is", "lambda", "nonlocal", "not",
                        "or", "pass", "raise", "return", "try", "while", "with", "yield",
                        "True", "False", "None", "self"};
            types = {"int", "float", "str", "bool", "list", "dict", "tuple", "set",
                     "bytes", "type", "range", "complex", "frozenset", "bytearray"};
            hash_comments = true;
        } else if (norm == "c" || norm == "cpp" || norm == "c++" || norm == "h" || norm == "hpp") {
            keywords = {"auto", "break", "case", "catch", "class", "const", "constexpr",
                        "continue", "decltype", "default", "delete", "do", "else", "enum",
                        "explicit", "extern", "final", "for", "friend", "goto", "if",
                        "inline", "mutable", "namespace", "new", "noexcept", "nullptr",
                        "operator", "override", "private", "protected", "public", "register",
                        "return", "sizeof", "static", "static_assert", "static_cast",
                        "struct", "switch", "template", "this", "throw", "try", "typedef",
                        "typeid", "typename", "union", "using", "virtual", "volatile",
                        "while", "true", "false", "NULL"};
            types = {"void", "int", "char", "short", "long", "float", "double", "bool",
                     "unsigned", "signed", "size_t", "uint8_t", "uint16_t", "uint32_t",
                     "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "string",
                     "vector", "map", "set", "list", "array", "shared_ptr", "unique_ptr"};
        } else if (norm == "java" || norm == "kotlin" || norm == "kt") {
            keywords = {"abstract", "assert", "break", "case", "catch", "class", "const",
                        "continue", "default", "do", "else", "enum", "extends", "final",
                        "finally", "for", "goto", "if", "implements", "import", "instanceof",
                        "interface", "native", "new", "package", "private", "protected",
                        "public", "return", "static", "strictfp", "super", "switch",
                        "synchronized", "this", "throw", "throws", "transient", "try",
                        "volatile", "while", "true", "false", "null",
                        "val", "var", "fun", "when", "object", "companion", "data", "sealed",
                        "override", "open", "internal", "suspend", "inline", "crossinline"};
            types = {"void", "int", "char", "short", "long", "float", "double", "boolean",
                     "byte", "String", "Integer", "Long", "Double", "Float", "Boolean",
                     "List", "Map", "Set", "Array", "ArrayList", "HashMap", "HashSet",
                     "Object", "Class", "Optional", "Stream"};
        } else if (norm == "rust" || norm == "rs") {
            keywords = {"as", "async", "await", "break", "const", "continue", "crate", "dyn",
                        "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in",
                        "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
                        "self", "Self", "static", "struct", "super", "trait", "true", "type",
                        "unsafe", "use", "where", "while", "macro_rules"};
            types = {"i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64",
                     "u128", "usize", "f32", "f64", "bool", "char", "str", "String",
                     "Vec", "Box", "Rc", "Arc", "Option", "Result", "HashMap", "HashSet"};
        } else if (norm == "go" || norm == "golang") {
            keywords = {"break", "case", "chan", "const", "continue", "default", "defer",
                        "else", "fallthrough", "for", "func", "go", "goto", "if", "import",
                        "interface", "map", "package", "range", "return", "select", "struct",
                        "switch", "type", "var", "true", "false", "nil", "iota"};
            types = {"bool", "byte", "complex64", "complex128", "error", "float32", "float64",
                     "int", "int8", "int16", "int32", "int64", "rune", "string",
                     "uint", "uint8", "uint16", "uint32", "uint64", "uintptr"};
        } else if (norm == "vala") {
            keywords = {"abstract", "as", "async", "base", "break", "case", "catch", "class",
                        "const", "construct", "continue", "default", "delegate", "delete",
                        "do", "dynamic", "else", "ensures", "enum", "errordomain", "extern",
                        "finally", "for", "foreach", "get", "global", "if", "in", "inline",
                        "interface", "internal", "is", "lock", "namespace", "new", "null",
                        "out", "override", "owned", "private", "protected", "public", "ref",
                        "requires", "return", "set", "signal", "sizeof", "static", "struct",
                        "switch", "this", "throw", "throws", "try", "typeof", "unowned",
                        "using", "var", "virtual", "void", "volatile", "weak", "while",
                        "with", "yield", "true", "false"};
            types = {"bool", "char", "double", "float", "int", "int8", "int16", "int32",
                     "int64", "long", "short", "size_t", "ssize_t", "string", "uchar",
                     "uint", "uint8", "uint16", "uint32", "uint64", "ulong", "unichar",
                     "ushort", "void"};
        } else if (norm == "ruby" || norm == "rb") {
            keywords = {"alias", "and", "begin", "break", "case", "class", "def", "defined?",
                        "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in",
                        "module", "next", "nil", "not", "or", "redo", "rescue", "retry",
                        "return", "self", "super", "then", "true", "undef", "unless", "until",
                        "when", "while", "yield", "require", "include", "extend", "attr_accessor",
                        "attr_reader", "attr_writer", "puts", "print"};
            types = {"Array", "Hash", "String", "Integer", "Float", "Symbol", "Proc",
                     "Lambda", "Fixnum", "Bignum", "Numeric", "TrueClass", "FalseClass",
                     "NilClass", "Range", "Regexp", "IO", "File", "Dir"};
            hash_comments = true;
        } else if (norm == "sh" || norm == "bash" || norm == "zsh" || norm == "shell") {
            keywords = {"if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                        "case", "esac", "in", "function", "return", "local", "export",
                        "source", "alias", "unalias", "set", "unset", "readonly", "shift",
                        "exit", "break", "continue", "trap", "eval", "exec", "true", "false"};
            types = {};
            hash_comments = true;
        } else if (norm == "css" || norm == "scss" || norm == "less") {
            keywords = {"important", "media", "import", "keyframes", "font-face", "supports",
                        "charset", "namespace", "page", "counter-style", "layer"};
            types = {};
        } else if (norm == "html" || norm == "xml" || norm == "svg") {
            // For markup languages, just do basic tag highlighting
            return highlight_markup_language(escaped, dark_theme);
        } else if (norm == "json") {
            return highlight_json(escaped, dark_theme);
        } else if (norm == "sql") {
            keywords = {"SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
                        "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "ADD", "INDEX", "VIEW",
                        "JOIN", "INNER", "LEFT", "RIGHT", "OUTER", "ON", "AS", "AND", "OR",
                        "NOT", "NULL", "IS", "IN", "BETWEEN", "LIKE", "ORDER", "BY", "GROUP",
                        "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "EXISTS",
                        "CASE", "WHEN", "THEN", "ELSE", "END", "ASC", "DESC", "PRIMARY", "KEY",
                        "FOREIGN", "REFERENCES", "CONSTRAINT", "DEFAULT", "CHECK", "UNIQUE",
                        "CASCADE", "TRUNCATE", "BEGIN", "COMMIT", "ROLLBACK", "GRANT", "REVOKE",
                        "WITH", "RECURSIVE", "RETURNING",
                        "select", "from", "where", "insert", "into", "values", "update", "set",
                        "delete", "create", "table", "drop", "alter", "add", "index", "view",
                        "join", "inner", "left", "right", "outer", "on", "as", "and", "or",
                        "not", "null", "is", "in", "between", "like", "order", "by", "group",
                        "having", "limit", "offset", "union", "all", "distinct", "exists",
                        "case", "when", "then", "else", "end", "asc", "desc", "primary", "key",
                        "foreign", "references", "constraint", "default", "check", "unique",
                        "cascade", "truncate", "begin", "commit", "rollback", "grant", "revoke",
                        "with", "recursive", "returning", "TRUE", "FALSE"};
            types = {"INTEGER", "TEXT", "REAL", "BLOB", "VARCHAR", "CHAR", "BOOLEAN", "DATE",
                     "TIMESTAMP", "DECIMAL", "NUMERIC", "BIGINT", "SMALLINT", "SERIAL",
                     "integer", "text", "real", "blob", "varchar", "char", "boolean", "date",
                     "timestamp", "decimal", "numeric", "bigint", "smallint", "serial"};
        } else if (norm == "php") {
            keywords = {"abstract", "and", "as", "break", "callable", "case", "catch", "class",
                        "clone", "const", "continue", "declare", "default", "do", "echo", "else",
                        "elseif", "empty", "enddeclare", "endfor", "endforeach", "endif",
                        "endswitch", "endwhile", "eval", "exit", "extends", "final", "finally",
                        "fn", "for", "foreach", "function", "global", "goto", "if", "implements",
                        "include", "include_once", "instanceof", "insteadof", "interface",
                        "isset", "list", "match", "namespace", "new", "or", "print", "private",
                        "protected", "public", "readonly", "require", "require_once", "return",
                        "static", "switch", "throw", "trait", "try", "unset", "use", "var",
                        "while", "xor", "yield", "true", "false", "null", "TRUE", "FALSE", "NULL"};
            types = {"int", "float", "string", "bool", "array", "object", "void", "mixed",
                     "never", "null", "self", "parent", "iterable"};
        } else {
            // Unknown language: return escaped without highlighting
            return escaped;
        }

        return highlight_code(escaped, keywords, types, line_comment, block_comment_start, block_comment_end, hash_comments, c_keyword, c_string, c_comment, c_number, c_function, c_type, c_operator);
    }

    private static string highlight_code(string escaped, string[] keywords, string[] types,
                                          string line_comment, string block_comment_start,
                                          string block_comment_end, bool hash_comments,
                                          string c_keyword, string c_string, string c_comment,
                                          string c_number, string c_function, string c_type,
                                          string c_operator) {
        var result = new StringBuilder();
        int i = 0;
        int len = escaped.length;

        // Pre-escape the comment markers for matching in escaped text
        string esc_line_comment = Markup.escape_text(line_comment);
        string esc_block_start = Markup.escape_text(block_comment_start);
        string esc_block_end = Markup.escape_text(block_comment_end);

        while (i < len) {
            // Block comments
            if (i + esc_block_start.length <= len && escaped[i:i + esc_block_start.length] == esc_block_start) {
                int end_idx = escaped.index_of(esc_block_end, i + esc_block_start.length);
                if (end_idx == -1) end_idx = len - esc_block_end.length;
                string comment = escaped[i:end_idx + esc_block_end.length];
                result.append(@"<span foreground='$c_comment'>$comment</span>");
                i = end_idx + esc_block_end.length;
                continue;
            }

            // Line comments
            if (i + esc_line_comment.length <= len && escaped[i:i + esc_line_comment.length] == esc_line_comment) {
                int nl = escaped.index_of("\n", i);
                if (nl == -1) nl = len;
                string comment = escaped[i:nl];
                result.append(@"<span foreground='$c_comment'>$comment</span>");
                i = nl;
                continue;
            }

            // Hash comments (Python, Ruby, Shell)
            if (hash_comments && escaped[i] == '#') {
                int nl = escaped.index_of("\n", i);
                if (nl == -1) nl = len;
                string comment = escaped[i:nl];
                result.append(@"<span foreground='$c_comment'>$comment</span>");
                i = nl;
                continue;
            }

            // Strings (double-quoted)
            if (escaped[i] == '"' || (i + 5 < len && escaped[i:i+6] == "&quot;")) {
                string open_delim;
                if (escaped[i] == '"') {
                    open_delim = "\"";
                } else {
                    open_delim = "&quot;";
                }
                int str_start = i;
                i += open_delim.length;
                bool found_end = false;
                while (i < len) {
                    if (escaped[i] == '\\') {
                        i += 2;
                        continue;
                    }
                    if (escaped[i] == '"' || (i + 5 < len && escaped[i:i+6] == "&quot;")) {
                        if (escaped[i] == '"') {
                            i += 1;
                        } else {
                            i += 6;
                        }
                        found_end = true;
                        break;
                    }
                    i++;
                }
                if (!found_end) i = len;
                string str_text = escaped[str_start:i];
                result.append(@"<span foreground='$c_string'>$str_text</span>");
                continue;
            }

            // Strings (single-quoted)  - &apos; is the escaped version
            if (escaped[i] == '\'' || (i + 5 < len && escaped[i:i+6] == "&apos;")) {
                string open_delim;
                if (escaped[i] == '\'') {
                    open_delim = "'";
                } else {
                    open_delim = "&apos;";
                }
                int str_start = i;
                i += open_delim.length;
                bool found_end = false;
                while (i < len) {
                    if (escaped[i] == '\\') {
                        i += 2;
                        continue;
                    }
                    if (escaped[i] == '\'' || (i + 5 < len && escaped[i:i+6] == "&apos;")) {
                        if (escaped[i] == '\'') {
                            i += 1;
                        } else {
                            i += 6;
                        }
                        found_end = true;
                        break;
                    }
                    i++;
                }
                if (!found_end) i = len;
                string str_text = escaped[str_start:i];
                result.append(@"<span foreground='$c_string'>$str_text</span>");
                continue;
            }

            // Backtick strings (template literals)
            if (escaped[i] == '`') {
                int str_start = i;
                i += 1;
                bool found_end = false;
                while (i < len) {
                    if (escaped[i] == '\\') {
                        i += 2;
                        continue;
                    }
                    if (escaped[i] == '`') {
                        i += 1;
                        found_end = true;
                        break;
                    }
                    i++;
                }
                if (!found_end) i = len;
                string str_text = escaped[str_start:i];
                result.append(@"<span foreground='$c_string'>$str_text</span>");
                continue;
            }

            // Numbers
            if (escaped[i].isdigit() || (escaped[i] == '.' && i + 1 < len && escaped[i+1].isdigit())) {
                int num_start = i;
                // Hex
                if (escaped[i] == '0' && i + 1 < len && (escaped[i+1] == 'x' || escaped[i+1] == 'X')) {
                    i += 2;
                    while (i < len && escaped[i].isxdigit()) i++;
                } else {
                    while (i < len && (escaped[i].isdigit() || escaped[i] == '.' || escaped[i] == '_')) i++;
                    // Suffixes like 'f', 'L', 'u', etc.
                    if (i < len && (escaped[i] == 'f' || escaped[i] == 'F' || escaped[i] == 'l' || escaped[i] == 'L' || escaped[i] == 'u' || escaped[i] == 'U')) i++;
                }
                string num_text = escaped[num_start:i];
                result.append(@"<span foreground='$c_number'>$num_text</span>");
                continue;
            }

            // Words: keywords, types, and function calls
            if (escaped[i].isalpha() || escaped[i] == '_') {
                int word_start = i;
                while (i < len && (escaped[i].isalnum() || escaped[i] == '_')) i++;
                string word = escaped[word_start:i];

                if (word in keywords) {
                    result.append(@"<span foreground='$c_keyword'>$word</span>");
                } else if (word in types) {
                    result.append(@"<span foreground='$c_type'>$word</span>");
                } else if (i < len && escaped[i] == '(') {
                    // Function call
                    result.append(@"<span foreground='$c_function'>$word</span>");
                } else {
                    result.append(word);
                }
                continue;
            }

            // Pango entities: &amp; &lt; &gt; etc - pass through
            if (escaped[i] == '&') {
                int amp_start = i;
                i++;
                while (i < len && escaped[i] != ';' && (i - amp_start) < 10) i++;
                if (i < len && escaped[i] == ';') i++;
                string entity = escaped[amp_start:i];
                result.append(@"<span foreground='$c_operator'>$entity</span>");
                continue;
            }

            // Operators and punctuation
            result.append_c(escaped[i]);
            i++;
        }

        return result.str;
    }

    private static string highlight_markup_language(string escaped, bool dark_theme) {
        string c_tag = dark_theme ? "#569CD6" : "#800000";
        string c_attr = dark_theme ? "#9CDCFE" : "#FF0000";
        string c_string = dark_theme ? "#CE9178" : "#0000FF";
        string c_comment = dark_theme ? "#6A9955" : "#008000";
        string c_content = dark_theme ? "#d4d4d4" : "#1e1e1e";

        var result = new StringBuilder();
        int i = 0;
        int len = escaped.length;

        while (i < len) {
            // Comments <!-- -->
            string comment_open = "&lt;!--";
            string comment_close = "--&gt;";
            if (i + comment_open.length <= len && escaped[i:i + comment_open.length] == comment_open) {
                int end_idx = escaped.index_of(comment_close, i + comment_open.length);
                if (end_idx == -1) end_idx = len - comment_close.length;
                string comment = escaped[i:end_idx + comment_close.length];
                result.append(@"<span foreground='$c_comment'>$comment</span>");
                i = end_idx + comment_close.length;
                continue;
            }

            // Tags
            string lt = "&lt;";
            string gt = "&gt;";
            if (i + lt.length <= len && escaped[i:i + lt.length] == lt) {
                int tag_start = i;
                result.append(@"<span foreground='$c_tag'>$lt</span>");
                i += lt.length;

                // Possible closing slash
                if (i < len && escaped[i] == '/') {
                    result.append(@"<span foreground='$c_tag'>/</span>");
                    i++;
                }

                // Tag name
                int name_start = i;
                while (i < len && escaped[i].isalnum() || (i < len && (escaped[i] == '-' || escaped[i] == '_' || escaped[i] == ':'))) i++;
                if (i > name_start) {
                    string tag_name = escaped[name_start:i];
                    result.append(@"<span foreground='$c_tag'>$tag_name</span>");
                }

                // Attributes and closing
                while (i < len) {
                    if (i + gt.length <= len && escaped[i:i + gt.length] == gt) {
                        // Self-closing check
                        if (i > 0 && escaped[i-1] == '/') {
                            // already appended the /
                        }
                        result.append(@"<span foreground='$c_tag'>$gt</span>");
                        i += gt.length;
                        break;
                    }

                    // Attribute strings
                    if (escaped[i] == '"' || escaped[i] == '\'') {
                        char quote = escaped[i];
                        int str_start = i;
                        i++;
                        while (i < len && escaped[i] != quote) i++;
                        if (i < len) i++; // closing quote
                        string attr_val = escaped[str_start:i];
                        result.append(@"<span foreground='$c_string'>$attr_val</span>");
                        continue;
                    }

                    // Attribute names
                    if (escaped[i].isalpha() || escaped[i] == '-' || escaped[i] == '_') {
                        int an_start = i;
                        while (i < len && (escaped[i].isalnum() || escaped[i] == '-' || escaped[i] == '_')) i++;
                        string attr_name = escaped[an_start:i];
                        result.append(@"<span foreground='$c_attr'>$attr_name</span>");
                        continue;
                    }

                    result.append_c(escaped[i]);
                    i++;
                }
                continue;
            }

            result.append_c(escaped[i]);
            i++;
        }

        return result.str;
    }

    private static string highlight_json(string escaped, bool dark_theme) {
        string c_key = dark_theme ? "#9CDCFE" : "#0451A5";
        string c_string = dark_theme ? "#CE9178" : "#A31515";
        string c_number = dark_theme ? "#B5CEA8" : "#098658";
        string c_keyword = dark_theme ? "#569CD6" : "#0000FF";

        var result = new StringBuilder();
        int i = 0;
        int len = escaped.length;

        while (i < len) {
            // Strings (keys and values)
            if (escaped[i] == '"' || (i + 5 < len && escaped[i:i+6] == "&quot;")) {
                string open_delim;
                if (escaped[i] == '"') {
                    open_delim = "\"";
                } else {
                    open_delim = "&quot;";
                }
                int str_start = i;
                i += open_delim.length;
                while (i < len) {
                    if (escaped[i] == '\\') {
                        i += 2;
                        continue;
                    }
                    if (escaped[i] == '"' || (i + 5 < len && escaped[i:i+6] == "&quot;")) {
                        if (escaped[i] == '"') i += 1; else i += 6;
                        break;
                    }
                    i++;
                }
                string str_text = escaped[str_start:i];

                // Check if this is a key (followed by colon)
                int j = i;
                while (j < len && escaped[j] == ' ') j++;
                if (j < len && escaped[j] == ':') {
                    result.append(@"<span foreground='$c_key'>$str_text</span>");
                } else {
                    result.append(@"<span foreground='$c_string'>$str_text</span>");
                }
                continue;
            }

            // Numbers
            if (escaped[i].isdigit() || (escaped[i] == '-' && i + 1 < len && escaped[i+1].isdigit())) {
                int num_start = i;
                if (escaped[i] == '-') i++;
                while (i < len && (escaped[i].isdigit() || escaped[i] == '.' || escaped[i] == 'e' || escaped[i] == 'E' || escaped[i] == '+' || escaped[i] == '-')) i++;
                string num_text = escaped[num_start:i];
                result.append(@"<span foreground='$c_number'>$num_text</span>");
                continue;
            }

            // Keywords: true, false, null
            if (i + 4 <= len && escaped[i:i+4] == "true") {
                result.append(@"<span foreground='$c_keyword'>true</span>");
                i += 4;
                continue;
            }
            if (i + 5 <= len && escaped[i:i+5] == "false") {
                result.append(@"<span foreground='$c_keyword'>false</span>");
                i += 5;
                continue;
            }
            if (i + 4 <= len && escaped[i:i+4] == "null") {
                result.append(@"<span foreground='$c_keyword'>null</span>");
                i += 4;
                continue;
            }

            result.append_c(escaped[i]);
            i++;
        }

        return result.str;
    }
}

}
