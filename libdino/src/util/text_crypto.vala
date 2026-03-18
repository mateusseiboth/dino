namespace Dino {

public class TextCrypto : Object {
    private const string AES_PREFIX = "dinoenc:v2:";
    private const string LEGACY_PREFIX = "dinoenc:v1:";
    private const string FIXED_KEY = "DINO_FIXED_AES_KEY_2026_FIXED_KEY";
    private const int AES_BLOCK_SIZE = 16;
    private const int AES_KEY_SIZE = 32;

    private static uint8[] get_fixed_key_bytes() {
        uint8[] key = new uint8[AES_KEY_SIZE];
        uint8[] key_src = (uint8[]) FIXED_KEY.data;
        for (int i = 0; i < AES_KEY_SIZE; i++) {
            key[i] = key_src[i];
        }
        return key;
    }

    private static uint8[] pkcs7_pad(uint8[] input, int input_len) {
        int padded_len = ((input_len / AES_BLOCK_SIZE) + 1) * AES_BLOCK_SIZE;
        uint8[] padded = new uint8[padded_len];
        for (int i = 0; i < input_len; i++) {
            padded[i] = input[i];
        }
        uint8 pad_value = (uint8) (padded_len - input_len);
        for (int i = input_len; i < padded_len; i++) {
            padded[i] = pad_value;
        }
        return padded;
    }

    private static int pkcs7_unpadded_len(uint8[] input) {
        int len = input.length;
        if (len == 0 || (len % AES_BLOCK_SIZE) != 0) return -1;

        int pad_value = (int) input[len - 1];
        if (pad_value <= 0 || pad_value > AES_BLOCK_SIZE) return -1;
        for (int i = len - pad_value; i < len; i++) {
            if ((int) input[i] != pad_value) return -1;
        }
        return len - pad_value;
    }

    private static char nibble_to_hex(uint8 n) {
        return (char) (n < 10 ? ('0' + n) : ('a' + (n - 10)));
    }

    private static int hex_to_nibble(char c) {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
        if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
        return -1;
    }

    public static bool is_encrypted_payload(string text) {
        return text.has_prefix(AES_PREFIX) || text.has_prefix(LEGACY_PREFIX);
    }

    private static string decrypt_legacy_v1(string incoming_text) {
        string hex = incoming_text.substring(LEGACY_PREFIX.length);
        if (hex.length == 0) return "";
        if ((hex.length % 2) != 0) return incoming_text;

        uint8[] key = (uint8[]) "DINO_FIXED_KEY_2026".data;
        int key_len = "DINO_FIXED_KEY_2026".length;
        int out_len = hex.length / 2;
        uint8[] out_bytes = new uint8[out_len + 1];

        for (int i = 0; i < out_len; i++) {
            int hi = hex_to_nibble(hex[2 * i]);
            int lo = hex_to_nibble(hex[2 * i + 1]);
            if (hi < 0 || lo < 0) return incoming_text;
            uint8 raw = (uint8) ((hi << 4) | lo);
            out_bytes[i] = (uint8) (raw ^ key[i % key_len]);
        }
        out_bytes[out_len] = 0;

        return (string) out_bytes;
    }

    public static string encrypt_text(string plain_text) {
        uint8[] plain_bytes = (uint8[]) plain_text.data;
        int plain_len = plain_text.length;
        uint8[] padded = pkcs7_pad(plain_bytes, plain_len);

        uint8[] iv = new uint8[AES_BLOCK_SIZE];
        Crypto.randomize(iv);

        uint8[] encrypted = new uint8[padded.length];
        try {
            Crypto.SymmetricCipher cipher = new Crypto.SymmetricCipher("AES256-CBC");
            cipher.set_key(get_fixed_key_bytes());
            cipher.set_iv(iv);
            cipher.encrypt(encrypted, padded);
        } catch (Error e) {
            warning("AES encryption failed: %s", e.message);
            return plain_text;
        }

        uint8[] payload = new uint8[iv.length + encrypted.length];
        for (int i = 0; i < iv.length; i++) {
            payload[i] = iv[i];
        }
        for (int i = 0; i < encrypted.length; i++) {
            payload[iv.length + i] = encrypted[i];
        }

        return AES_PREFIX + Base64.encode(payload);
    }

    public static string decrypt_text_if_needed(string incoming_text) {
        if (!is_encrypted_payload(incoming_text)) {
            return incoming_text;
        }
        if (incoming_text.has_prefix(LEGACY_PREFIX)) {
            return decrypt_legacy_v1(incoming_text);
        }

        string payload_b64 = incoming_text.substring(AES_PREFIX.length);
        if (payload_b64.length == 0) {
            return incoming_text;
        }

        uint8[] payload = Base64.decode(payload_b64);
        if (payload.length < AES_BLOCK_SIZE || ((payload.length - AES_BLOCK_SIZE) % AES_BLOCK_SIZE) != 0) {
            return incoming_text;
        }

        int encrypted_len = payload.length - AES_BLOCK_SIZE;
        uint8[] iv = new uint8[AES_BLOCK_SIZE];
        uint8[] encrypted = new uint8[encrypted_len];

        for (int i = 0; i < AES_BLOCK_SIZE; i++) {
            iv[i] = payload[i];
        }
        for (int i = 0; i < encrypted_len; i++) {
            encrypted[i] = payload[AES_BLOCK_SIZE + i];
        }

        uint8[] decrypted = new uint8[encrypted_len];
        try {
            Crypto.SymmetricCipher cipher = new Crypto.SymmetricCipher("AES256-CBC");
            cipher.set_key(get_fixed_key_bytes());
            cipher.set_iv(iv);
            cipher.decrypt(decrypted, encrypted);
        } catch (Error e) {
            warning("AES decryption failed: %s", e.message);
            return incoming_text;
        }

        int unpadded_len = pkcs7_unpadded_len(decrypted);
        if (unpadded_len < 0) {
            return incoming_text;
        }

        uint8[] out_bytes = new uint8[unpadded_len + 1];
        for (int i = 0; i < unpadded_len; i++) {
            out_bytes[i] = decrypted[i];
        }
        out_bytes[unpadded_len] = 0;

        return (string) out_bytes;
    }
}

}
