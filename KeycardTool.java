import apdu4j.pcsc.TerminalManager;
import java.math.BigInteger;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HexFormat;
import javax.smartcardio.CardChannel;
import javax.smartcardio.CardTerminal;
import javax.smartcardio.CommandAPDU;
import javax.smartcardio.ResponseAPDU;
import org.bouncycastle.asn1.x9.X9ECParameters;
import org.bouncycastle.crypto.digests.SHA256Digest;
import org.bouncycastle.crypto.ec.CustomNamedCurves;
import org.bouncycastle.crypto.params.ECDomainParameters;
import org.bouncycastle.crypto.params.ECPrivateKeyParameters;
import org.bouncycastle.crypto.signers.ECDSASigner;
import org.bouncycastle.crypto.signers.HMacDSAKCalculator;
import org.bouncycastle.math.ec.ECAlgorithms;
import org.bouncycastle.math.ec.ECPoint;

/**
 * The card steps GlobalPlatformPro does not cover. Run from source against gp.jar, which bundles
 * the two libraries used here (BouncyCastle and apdu4j):
 *
 *   java -cp gp.jar KeycardTool.java generate|status|load-ident
 *
 * None of these commands log in to the card manager, so none can count toward its lockout.
 */
public class KeycardTool {
  // The test CA of keycard-cli's "load-ident --test". Its private key is public, so a certificate
  // it signs proves nothing: wallets show the card as not genuine until the user approves it.
  static final BigInteger TEST_CA_KEY =
      new BigInteger("a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2", 16);

  static final byte[] KEYCARD_AID = HexFormat.of().parseHex("A00000080400010101");
  static final byte[] IDENT_AID = HexFormat.of().parseHex("A00000080400010401");

  static final int PUBLIC_KEY_LENGTH = 33;
  static final int CERTIFICATE_LENGTH = 98;

  static final int SW_OK = 0x9000;
  static final int SW_NOT_FOUND = 0x6A82;
  static final int SW_NO_CERTIFICATE = 0x6985;

  static final X9ECParameters SECP256K1 = CustomNamedCurves.getByName("secp256k1");
  static final ECDomainParameters CURVE =
      new ECDomainParameters(SECP256K1.getCurve(), SECP256K1.getG(), SECP256K1.getN(), SECP256K1.getH());

  public static void main(String[] args) {
    try {
      switch (args.length == 1 ? args[0] : "") {
        case "generate" -> System.out.println(hex(newIdentity()));
        case "status" -> System.out.println(status(connect()));
        case "load-ident" -> loadIdent(connect());
        default -> {
          System.err.println("usage: KeycardTool generate|status|load-ident");
          System.exit(2);
        }
      }
    } catch (Exception e) {
      System.err.println("error: " + e.getMessage());
      System.exit(1);
    }
  }

  /**
   * What the Ident applet stores: the certificate followed by the identity private key.
   * certificate = identity public key (33, compressed) | r (32) | s (32) | recovery id (1),
   * where (r, s) is the CA's signature over SHA-256(identity public key).
   */
  static byte[] newIdentity() throws Exception {
    BigInteger n = CURVE.getN();
    BigInteger identityKey;
    do {
      identityKey = new BigInteger(256, new SecureRandom());
    } while (identityKey.signum() == 0 || identityKey.compareTo(n) >= 0);
    byte[] identityPublic = CURVE.getG().multiply(identityKey).getEncoded(true);
    byte[] hash = MessageDigest.getInstance("SHA-256").digest(identityPublic);

    ECDSASigner signer = new ECDSASigner(new HMacDSAKCalculator(new SHA256Digest()));
    signer.init(true, new ECPrivateKeyParameters(TEST_CA_KEY, CURVE));
    BigInteger[] signature = signer.generateSignature(hash);
    BigInteger r = signature[0];
    BigInteger s = signature[1];
    // keycard-go emits the low-S form; a verifier may insist on it.
    if (s.compareTo(n.shiftRight(1)) > 0) {
      s = n.subtract(s);
    }

    byte[] out = new byte[CERTIFICATE_LENGTH + 32];
    System.arraycopy(identityPublic, 0, out, 0, PUBLIC_KEY_LENGTH);
    System.arraycopy(to32Bytes(r), 0, out, 33, 32);
    System.arraycopy(to32Bytes(s), 0, out, 65, 32);
    out[97] = recoveryId(hash, r, s, CURVE.getG().multiply(TEST_CA_KEY));
    System.arraycopy(to32Bytes(identityKey), 0, out, CERTIFICATE_LENGTH, 32);
    return out;
  }

  /** The card recovers the CA key from the signature; this is the hint that picks the right candidate. */
  static byte recoveryId(byte[] hash, BigInteger r, BigInteger s, ECPoint signerPublic) {
    BigInteger n = CURVE.getN();
    BigInteger e = new BigInteger(1, hash);
    BigInteger rInverse = r.modInverse(n);
    for (int id = 0; id < 2; id++) {
      byte[] encoded = new byte[33];
      encoded[0] = (byte) (0x02 | id);
      System.arraycopy(to32Bytes(r), 0, encoded, 1, 32);
      ECPoint point = CURVE.getCurve().decodePoint(encoded);
      ECPoint recovered = ECAlgorithms.sumOfTwoMultiplies(
          CURVE.getG(), e.negate().multiply(rInverse).mod(n), point, s.multiply(rInverse).mod(n));
      if (recovered.equals(signerPublic)) {
        return (byte) id;
      }
    }
    throw new IllegalStateException("could not compute the signature's recovery id");
  }

  static CardChannel connect() throws Exception {
    String wanted = System.getenv("GP_READER");
    for (CardTerminal terminal : TerminalManager.getTerminalFactory().terminals().list()) {
      if (!terminal.isCardPresent() || (wanted != null && !terminal.getName().contains(wanted))) {
        continue;
      }
      return terminal.connect("*").getBasicChannel();
    }
    throw new IllegalStateException("no card found. Check that the reader is plugged in and a card is in it.");
  }

  static ResponseAPDU select(CardChannel card, byte[] aid) throws Exception {
    return card.transmit(new CommandAPDU(0x00, 0xA4, 0x04, 0x00, aid, 256));
  }

  /** Prints absent, no-certificate, uninitialized or initialized. */
  static String status(CardChannel card) throws Exception {
    ResponseAPDU response = select(card, KEYCARD_AID);
    if (response.getSW() == SW_NOT_FOUND) {
      return "absent";
    }
    if (response.getSW() == SW_NO_CERTIFICATE) {
      return "no-certificate";
    }
    requireOk(response, "selecting the Keycard applet");
    byte[] data = response.getData();
    // Before 4.0 a card with no PIN answers with just its public key.
    if (data.length == 0 || (data[0] & 0xFF) == 0x80) {
      return "uninitialized";
    }
    // 4.0 always answers with the info template and flags initialization in the 0x8C status byte.
    int header = (data[1] & 0xFF) == 0x81 ? 3 : 2;
    for (int i = header; i + 1 < data.length; ) {
      int tag = data[i] & 0xFF;
      int length = data[i + 1] & 0xFF;
      if (tag == 0x8C && length >= 1) {
        return (data[i + 2] & 0x10) != 0 ? "initialized" : "uninitialized";
      }
      i += 2 + length;
    }
    return "initialized";
  }

  static void loadIdent(CardChannel card) throws Exception {
    ResponseAPDU response = select(card, IDENT_AID);
    requireOk(response, "selecting the Ident applet");
    if (response.getData().length > 0) {
      throw new IllegalStateException("this card already has an identity certificate; it can only be written once");
    }

    byte[] identity = newIdentity();
    requireOk(card.transmit(new CommandAPDU(0x80, 0xE2, 0x00, 0x00, identity)), "storing the certificate");

    String certificate = hex(Arrays.copyOf(identity, CERTIFICATE_LENGTH));
    response = select(card, KEYCARD_AID);
    requireOk(response, "selecting the Keycard applet");
    if (!hex(response.getData()).contains(certificate)) {
      throw new IllegalStateException("the Keycard applet does not report the certificate that was just stored");
    }
    System.out.println("Identity public key: 0x" + certificate.substring(0, PUBLIC_KEY_LENGTH * 2));
  }

  static void requireOk(ResponseAPDU response, String action) {
    if (response.getSW() != SW_OK) {
      throw new IllegalStateException(action + " failed: 0x" + Integer.toHexString(response.getSW()).toUpperCase());
    }
  }

  static byte[] to32Bytes(BigInteger value) {
    byte[] raw = value.toByteArray();
    byte[] out = new byte[32];
    int length = Math.min(raw.length, 32);
    System.arraycopy(raw, raw.length - length, out, 32 - length, length);
    return out;
  }

  static String hex(byte[] bytes) {
    return HexFormat.of().formatHex(bytes);
  }
}
