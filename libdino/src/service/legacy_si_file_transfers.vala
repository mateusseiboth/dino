using Gee;
using Xmpp;
using Xmpp.Xep;

using Dino.Entities;

namespace Dino {

public class LegacySiFileSender : FileSender, Object {

    private const string SI_NS = "http://jabber.org/protocol/si";
    private const string SI_FT_NS = "http://jabber.org/protocol/si/profile/file-transfer";
    private const string FEATURE_NEG_NS = "http://jabber.org/protocol/feature-neg";
    private const string IBB_NS = "http://jabber.org/protocol/ibb";
    private const string S5B_NS = "http://jabber.org/protocol/bytestreams";

    private StreamInteractor stream_interactor;

    private class LegacySiSendData : FileSendData {
        public Jid target_jid { get; set; }
        public Jid peer_full_jid { get; set; }
        public string sid { get; set; }
    }

    public LegacySiFileSender(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
    }

    private async Jid? select_target_resource(Conversation conversation) {
        XmppStream? stream = stream_interactor.get_stream(conversation.account);
        if (stream == null) return null;

        Gee.List<Jid>? resources = stream.get_flag(Presence.Flag.IDENTITY).get_resources(conversation.counterpart);
        if (resources == null || resources.size == 0) return null;

        ServiceDiscovery.Module disco = stream.get_module(ServiceDiscovery.Module.IDENTITY);
        foreach (Jid full_jid in resources) {
            bool has_si = yield disco.has_entity_feature(stream, full_jid, SI_NS);
            bool has_si_ft = yield disco.has_entity_feature(stream, full_jid, SI_FT_NS);
            bool has_ibb = yield disco.has_entity_feature(stream, full_jid, IBB_NS);
            if (has_si && has_si_ft && has_ibb) {
                return full_jid;
            }
        }

        // Fallback: some clients don't advertise all legacy features correctly.
        return resources[0];
    }

    public async bool is_upload_available(Conversation conversation) {
        if (conversation.type_ != Conversation.Type.CHAT) return false;
        return (yield select_target_resource(conversation)) != null;
    }

    public async long get_file_size_limit(Conversation conversation) {
        if (yield is_upload_available(conversation)) {
            return int.MAX;
        }
        return -1;
    }

    public async bool can_send(Conversation conversation, FileTransfer file_transfer) {
        return yield is_upload_available(conversation);
    }

    public async bool can_encrypt(Conversation conversation, FileTransfer file_transfer) {
        return false;
    }

    public async FileSendData? prepare_send_file(Conversation conversation, FileTransfer file_transfer, FileMeta file_meta) throws FileSendError {
        Jid? peer_full_jid = yield select_target_resource(conversation);
        if (peer_full_jid == null) {
            throw new FileSendError.UPLOAD_FAILED("No target resource for legacy SI transfer");
        }

        return new LegacySiSendData() {
            // Prefer full JID for legacy SI; some servers reject bare JID offers.
            target_jid = peer_full_jid,
            peer_full_jid = peer_full_jid,
            sid = Xmpp.random_uuid()
        };
    }

    public async void send_file(Conversation conversation, FileTransfer file_transfer, FileSendData file_send_data, FileMeta file_meta) throws FileSendError {
        LegacySiSendData? send_data = file_send_data as LegacySiSendData;
        if (send_data == null) {
            throw new FileSendError.UPLOAD_FAILED("Invalid legacy SI send data");
        }

        XmppStream? stream = stream_interactor.get_stream(file_transfer.account);
        if (stream == null) {
            throw new FileSendError.UPLOAD_FAILED("No stream available");
        }

        string safe_name = file_transfer.server_file_name;
        if (safe_name == null || safe_name.strip() == "") {
            safe_name = "file.bin";
        }

        StanzaNode file_node = new StanzaNode.build("file", SI_FT_NS)
            .add_self_xmlns()
            .put_attribute("name", safe_name)
            .put_attribute("size", file_meta.size.to_string());

        var x_form = new StanzaNode.build("x", DataForms.NS_URI)
                .add_self_xmlns()
                .put_attribute("type", "form")
                .put_node(
                    new StanzaNode.build("field", DataForms.NS_URI)
                        .put_attribute("var", "stream-method")
                        .put_attribute("type", "list-single")
                        .put_node(
                            new StanzaNode.build("option", DataForms.NS_URI)
                                .put_node(new StanzaNode.build("value", DataForms.NS_URI).put_node(new StanzaNode.text(IBB_NS)))
                        )
                        .put_node(
                            new StanzaNode.build("option", DataForms.NS_URI)
                                .put_node(new StanzaNode.build("value", DataForms.NS_URI).put_node(new StanzaNode.text(S5B_NS)))
                        )
                );

        StanzaNode si = new StanzaNode.build("si", SI_NS)
                .add_self_xmlns()
                .put_attribute("id", send_data.sid)
                .put_attribute("profile", SI_FT_NS)
                .put_attribute("mime-type", file_meta.content_type != null ? file_meta.content_type.get_mime_type() : "application/octet-stream")
                .put_node(file_node)
                .put_node(new StanzaNode.build("feature", FEATURE_NEG_NS).add_self_xmlns().put_node(x_form));

        Iq.Stanza iq = new Iq.Stanza.set(si) { to = send_data.target_jid };
        Iq.Stanza result_iq = yield stream.get_module(Iq.Module.IDENTITY).send_iq_async(stream, iq);
        Jid bare_jid = conversation.counterpart;
        if (result_iq.is_error() && !send_data.target_jid.equals(bare_jid)) {
            ErrorStanza? error_stanza = ErrorStanza.from_stanza(result_iq.stanza);
            if (error_stanza != null && (
                    error_stanza.condition == ErrorStanza.CONDITION_NOT_ALLOWED ||
                    error_stanza.condition == ErrorStanza.CONDITION_SERVICE_UNAVAILABLE ||
                    error_stanza.condition == ErrorStanza.CONDITION_RECIPIENT_UNAVAILABLE)) {
                warning("Legacy SI retry with bare JID %s after %s on %s", bare_jid.to_string(), error_stanza.condition, send_data.target_jid.to_string());
                Iq.Stanza retry_iq = new Iq.Stanza.set(si, send_data.sid + "-retry") { to = bare_jid };
                result_iq = yield stream.get_module(Iq.Module.IDENTITY).send_iq_async(stream, retry_iq);
            }
        }
        if (result_iq.is_error()) {
            throw new FileSendError.UPLOAD_FAILED("Legacy SI offer rejected: " + result_iq.stanza.to_string());
        }

        string? selected_stream_method = result_iq.stanza.get_deep_string_content(
            SI_NS + ":si", FEATURE_NEG_NS + ":feature", DataForms.NS_URI + ":x", DataForms.NS_URI + ":field", DataForms.NS_URI + ":value"
        );
        if (selected_stream_method == null) {
            // Some clients reply without echoing the form; default to IBB.
            selected_stream_method = IBB_NS;
        }

        Jid peer_for_stream = result_iq.from != null ? result_iq.from : send_data.target_jid;

        if (selected_stream_method != IBB_NS) {
            throw new FileSendError.UPLOAD_FAILED("Unsupported legacy stream method selected: " + selected_stream_method);
        }

        InBandBytestreams.Connection connection = InBandBytestreams.Connection.create(stream, peer_for_stream, send_data.sid, 4096, true);

        try {
            yield connection.output_stream.splice_async(file_transfer.input_stream, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET);
            yield connection.input_stream.close_async();
        } catch (Error e) {
            throw new FileSendError.UPLOAD_FAILED("Legacy SI/IBB transfer failed: " + e.message);
        }
    }

    public int get_id() { return 3; }

    public float get_priority() { return 10; }
}

public class LegacySiFileProvider : FileProvider, Object {

    private const string SI_NS = "http://jabber.org/protocol/si";
    private const string SI_FT_NS = "http://jabber.org/protocol/si/profile/file-transfer";
    private const string FEATURE_NEG_NS = "http://jabber.org/protocol/feature-neg";
    private const string IBB_NS = "http://jabber.org/protocol/ibb";

    private StreamInteractor stream_interactor;
    private HashMap<string, IncomingTransfer> incoming_transfers = new HashMap<string, IncomingTransfer>();

    private class IncomingTransfer : Object {
        public InBandBytestreams.Connection connection { get; set; }
        public FileMeta file_meta { get; set; }
    }

    private class LegacySiReceiverModule : XmppStreamModule, Iq.Handler {
        public static Xmpp.ModuleIdentity<LegacySiReceiverModule> IDENTITY = new Xmpp.ModuleIdentity<LegacySiReceiverModule>(SI_NS, "legacy_si_receiver_module");

        private weak LegacySiFileProvider provider;
        private Account account;

        public LegacySiReceiverModule(LegacySiFileProvider provider, Account account) {
            this.provider = provider;
            this.account = account;
        }

        public override void attach(XmppStream stream) {
            stream.get_module(Iq.Module.IDENTITY).register_for_namespace(SI_NS, this);
            stream.get_module(ServiceDiscovery.Module.IDENTITY).add_feature(stream, SI_NS);
            stream.get_module(ServiceDiscovery.Module.IDENTITY).add_feature(stream, SI_FT_NS);
            stream.get_module(ServiceDiscovery.Module.IDENTITY).add_feature(stream, IBB_NS);
        }

        public override void detach(XmppStream stream) {
            stream.get_module(Iq.Module.IDENTITY).unregister_from_namespace(SI_NS, this);
        }

        public override string get_ns() { return SI_NS; }
        public override string get_id() { return IDENTITY.id; }

        public async override void on_iq_set(XmppStream stream, Iq.Stanza iq) {
            if (provider == null) {
                stream.get_module(Iq.Module.IDENTITY).send_iq(stream, new Iq.Stanza.error(iq, new ErrorStanza.service_unavailable()) { to = iq.from });
                return;
            }

            debug("Legacy SI incoming offer from %s", iq.from != null ? iq.from.to_string() : "(null)");

            StanzaNode? si = iq.stanza.get_subnode("si", SI_NS);
            if (si == null) {
                stream.get_module(Iq.Module.IDENTITY).send_iq(stream, new Iq.Stanza.error(iq, new ErrorStanza.bad_request("missing si node")) { to = iq.from });
                return;
            }

            string? profile = si.get_attribute("profile");
            string? sid = si.get_attribute("id");
            if (profile != SI_FT_NS || sid == null || sid == "") {
                warning("Legacy SI invalid offer: profile=%s sid=%s", profile, sid);
                stream.get_module(Iq.Module.IDENTITY).send_iq(stream, new Iq.Stanza.error(iq, new ErrorStanza.bad_request("invalid si profile or sid")) { to = iq.from });
                return;
            }

            StanzaNode? file_node = si.get_subnode("file", SI_FT_NS);
            if (file_node == null || iq.from == null) {
                stream.get_module(Iq.Module.IDENTITY).send_iq(stream, new Iq.Stanza.error(iq, new ErrorStanza.bad_request("missing file metadata")) { to = iq.from });
                return;
            }

            string? file_name = file_node.get_attribute("name");
            string? size_attr = file_node.get_attribute("size");
            int64 file_size = -1;
            if (size_attr != null) {
                try {
                    file_size = int64.parse(size_attr);
                } catch (Error e) {
                    file_size = -1;
                }
            }

            StanzaNode? feature = si.get_subnode("feature", FEATURE_NEG_NS);
            StanzaNode? x = feature != null ? feature.get_subnode("x", DataForms.NS_URI) : null;
            bool offers_ibb = feature == null || x == null;
            if (x != null) {
                foreach (StanzaNode field in x.get_subnodes("field", DataForms.NS_URI)) {
                    if (field.get_attribute("var") != "stream-method") {
                        continue;
                    }
                    foreach (StanzaNode option in field.get_subnodes("option", DataForms.NS_URI)) {
                        StanzaNode? value_node = option.get_subnode("value", DataForms.NS_URI);
                        if (value_node != null && value_node.get_string_content() == IBB_NS) {
                            offers_ibb = true;
                            break;
                        }
                    }
                    foreach (StanzaNode value in field.get_subnodes("value", DataForms.NS_URI)) {
                        if (value.get_string_content() == IBB_NS) {
                            offers_ibb = true;
                            break;
                        }
                    }
                }
            }

            if (!offers_ibb) {
                warning("Legacy SI rejected: sender did not offer IBB sid=%s from=%s", sid, iq.from.to_string());
                stream.get_module(Iq.Module.IDENTITY).send_iq(stream, new Iq.Stanza.error(iq, new ErrorStanza.not_acceptable("no supported stream-method")) { to = iq.from });
                return;
            }

            debug("Legacy SI accepted sid=%s name=%s size=%lld from=%s", sid, file_name ?? "file.bin", file_size, iq.from.to_string());

            InBandBytestreams.Connection connection = InBandBytestreams.Connection.create(stream, iq.from, sid, 65535, false);

            string transfer_id = random_uuid();
            var file_meta = new FileMeta();
            file_meta.file_name = file_name != null && file_name.strip() != "" ? file_name : "file.bin";
            file_meta.size = file_size;

            provider.register_incoming_transfer(transfer_id, connection, file_meta);

            StanzaNode result_form = new StanzaNode.build("x", DataForms.NS_URI)
                .add_self_xmlns()
                .put_attribute("type", "submit")
                .put_node(new StanzaNode.build("field", DataForms.NS_URI)
                    .put_attribute("var", "stream-method")
                    .put_node(new StanzaNode.build("value", DataForms.NS_URI)
                        .put_node(new StanzaNode.text(IBB_NS))));

            StanzaNode result_si = new StanzaNode.build("si", SI_NS)
                .add_self_xmlns()
                .put_attribute("id", sid)
                .put_node(new StanzaNode.build("feature", FEATURE_NEG_NS)
                    .add_self_xmlns()
                    .put_node(result_form));

            stream.get_module(Iq.Module.IDENTITY).send_iq(stream, new Iq.Stanza.result(iq, result_si) { to = iq.from });

            provider.emit_incoming_offer(account, transfer_id, iq.from, file_meta);
        }
    }

    public LegacySiFileProvider(StreamInteractor stream_interactor) {
        this.stream_interactor = stream_interactor;
        stream_interactor.module_manager.initialize_account_modules.connect((account, modules) => {
            modules.add(new LegacySiReceiverModule(this, account));
        });
    }

    public void register_incoming_transfer(string transfer_id, InBandBytestreams.Connection connection, FileMeta file_meta) {
        incoming_transfers[transfer_id] = new IncomingTransfer() {
            connection = connection,
            file_meta = file_meta
        };
    }

    public void emit_incoming_offer(Account account, string transfer_id, Jid from, FileMeta file_meta) {
        ConversationManager conversation_manager = stream_interactor.get_module(ConversationManager.IDENTITY);
        Conversation? conversation = conversation_manager.get_conversation(from.bare_jid, account, Conversation.Type.CHAT);
        if (conversation == null) {
            conversation = conversation_manager.create_conversation(from.bare_jid, account, Conversation.Type.CHAT);
        }
        debug("Legacy SI file_incoming id=%s from=%s name=%s size=%lld", transfer_id, from.to_string(), file_meta.file_name, file_meta.size);
        var now = new DateTime.now_utc();
        file_incoming(transfer_id, from.bare_jid, now, now, conversation, new FileReceiveData(), file_meta);
    }

    public Encryption get_encryption(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) {
        return Encryption.NONE;
    }

    public FileMeta get_file_meta(FileTransfer file_transfer) throws FileReceiveError {
        IncomingTransfer? transfer = incoming_transfers[file_transfer.info];
        if (transfer == null) {
            throw new FileReceiveError.GET_METADATA_FAILED("Legacy SI transfer not found");
        }
        return transfer.file_meta;
    }

    public FileReceiveData? get_file_receive_data(FileTransfer file_transfer) {
        return new FileReceiveData();
    }

    public async FileMeta get_meta_info(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) throws FileReceiveError {
        return file_meta;
    }

    public async InputStream download(FileTransfer file_transfer, FileReceiveData receive_data, FileMeta file_meta) throws IOError {
        IncomingTransfer? transfer = incoming_transfers[file_transfer.info];
        if (transfer == null) {
            throw new IOError.NOT_FOUND("Legacy SI transfer not found");
        }
        debug("Legacy SI download start info=%s name=%s size=%lld", file_transfer.info, file_meta.file_name, file_meta.size);
        if (file_meta.size > 0) {
            return new LimitInputStream(transfer.connection.input_stream, file_meta.size);
        }
        return transfer.connection.input_stream;
    }

    public int get_id() {
        return 4;
    }
}

}