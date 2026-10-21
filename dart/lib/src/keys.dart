import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'der.dart';

/// Algorithm name sent to BaridiMob for 2048-bit device keys.
const String devkeyAlgorithm = 'RSA 2048';

/// Base64 SHA-256 of [devkeyAlgorithm], as expected by the login endpoint.
const String devkeyAlgorithmHash =
    '2irTxfGZWzVtenv242nedCNNC9k3M64egLmFRV8V4tk=';

/// A device identity: the RSA key pair that signs every request.
class DeviceKeys {
  /// Creates a device identity from its parts.
  const DeviceKeys({
    required this.devid,
    required this.privateKeyPem,
    required this.devkey,
    required this.devkeyAlgorithm,
    required this.devkeyAlgorithmHash,
  });

  /// Random device id (UUID v4).
  final String devid;

  /// Private key in PKCS#8 PEM format. Treat it as a secret.
  final String privateKeyPem;

  /// Public key as sent to BaridiMob: hex of the PKCS#1 `RSAPublicKey` DER.
  final String devkey;

  /// `RSA 2048` (or `RSA 512` for the legacy backend).
  final String devkeyAlgorithm;

  /// Base64 SHA-256 of [devkeyAlgorithm].
  final String devkeyAlgorithmHash;
}

/// Base64 SHA-256 of an algorithm name, for example [devkeyAlgorithm].
String algorithmHash(String algorithm) =>
    base64Encode(_sha256(utf8.encode(algorithm)));

/// Hex SHA-256 of a UTF-8 string.
String sha256Hex(String value) => _hex(_sha256(utf8.encode(value)));

/// Derives the `devkey` sent to BaridiMob from a public key in SPKI PEM format
/// (`-----BEGIN PUBLIC KEY-----`).
String deriveDevkey(String publicKeyPem) {
  final der = _pemBody(publicKeyPem, const ['PUBLIC KEY']).bytes;
  final spki = DerReader(der).next().children;
  spki.next(); // AlgorithmIdentifier
  final bitString = spki.next();
  if (bitString.tag != derTagBitString || bitString.value.isEmpty) {
    throw const FormatException('Invalid SPKI public key');
  }
  return _hex(bitString.value.sublist(1));
}

/// Generates a new device identity with a fresh RSA key pair.
///
/// Key generation is CPU intensive (around a second for 2048 bits). In a
/// Flutter app the client runs it in a background isolate for you.
DeviceKeys generateDeviceKeys({int bits = 2048}) {
  if (bits != 2048 && bits != 512) {
    throw ArgumentError.value(bits, 'bits', 'Only 2048 and 512 are supported');
  }
  final key = RsaKey.generate(bits);
  final algorithm = bits == 2048 ? 'RSA 2048' : 'RSA 512';
  return DeviceKeys(
    devid: randomUuid(),
    privateKeyPem: key.toPkcs8Pem(),
    devkey: key.devkey,
    devkeyAlgorithm: algorithm,
    devkeyAlgorithmHash: algorithmHash(algorithm),
  );
}

/// RSA private key material, read from or written to PEM.
class RsaKey {
  RsaKey({
    required this.n,
    required this.e,
    required this.d,
    required this.p,
    required this.q,
  });

  /// Generates a key pair with public exponent 65537.
  factory RsaKey.generate(int bits) {
    final generator = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
        _secureRandom(),
      ));
    final pair = generator.generateKeyPair();
    final public = pair.publicKey;
    final private = pair.privateKey;
    return RsaKey(
      n: public.modulus!,
      e: public.publicExponent!,
      d: private.privateExponent!,
      p: private.p!,
      q: private.q!,
    );
  }

  /// Parses a private key in PKCS#8 (`BEGIN PRIVATE KEY`) or
  /// PKCS#1 (`BEGIN RSA PRIVATE KEY`) PEM format.
  factory RsaKey.fromPem(String pem) {
    final body = _pemBody(pem, const ['PRIVATE KEY', 'RSA PRIVATE KEY']);
    var der = body.bytes;
    if (body.label == 'PRIVATE KEY') {
      final info = DerReader(der).next().children;
      info.next(); // version
      final algorithm = info.next();
      if (!_sameBytes(
          derTlv(algorithm.tag, algorithm.value), rsaEncryptionAlgorithm)) {
        throw const FormatException('Only RSA private keys are supported');
      }
      final octets = info.next();
      if (octets.tag != derTagOctetString) {
        throw const FormatException('Invalid PKCS#8 private key');
      }
      der = octets.value;
    }
    final fields = DerReader(der).next().children;
    fields.next(); // version
    return RsaKey(
      n: fields.next().integer,
      e: fields.next().integer,
      d: fields.next().integer,
      p: fields.next().integer,
      q: fields.next().integer,
    );
  }

  final BigInt n;
  final BigInt e;
  final BigInt d;
  final BigInt p;
  final BigInt q;

  int get bitLength => n.bitLength;

  /// Hex of the PKCS#1 `RSAPublicKey` DER, the format BaridiMob expects.
  String get devkey => _hex(derSequence([derInteger(n), derInteger(e)]));

  String toPkcs8Pem() {
    final rsaPrivateKey = derSequence([
      derInteger(BigInt.zero),
      derInteger(n),
      derInteger(e),
      derInteger(d),
      derInteger(p),
      derInteger(q),
      derInteger(d % (p - BigInt.one)),
      derInteger(d % (q - BigInt.one)),
      derInteger(q.modInverse(p)),
    ]);
    final info = derSequence([
      derInteger(BigInt.zero),
      rsaEncryptionAlgorithm,
      derTlv(derTagOctetString, rsaPrivateKey),
    ]);
    return _pem('PRIVATE KEY', info);
  }

  /// Public key in SPKI PEM format (`BEGIN PUBLIC KEY`).
  String toPublicPem() {
    final rsaPublicKey = derSequence([derInteger(n), derInteger(e)]);
    final spki = derSequence([
      rsaEncryptionAlgorithm,
      derTlv(derTagBitString, [0, ...rsaPublicKey]),
    ]);
    return _pem('PUBLIC KEY', spki);
  }

  RSAPrivateKey toPointyCastle() => RSAPrivateKey(n, d, p, q);
}

/// Random UUID v4 from a cryptographically secure source.
String randomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = _hex(bytes);
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

SecureRandom _secureRandom() {
  final seed = Random.secure();
  return FortunaRandom()
    ..seed(KeyParameter(
      Uint8List.fromList(List<int>.generate(32, (_) => seed.nextInt(256))),
    ));
}

Uint8List _sha256(List<int> bytes) =>
    SHA256Digest().process(Uint8List.fromList(bytes));

String _hex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _pem(String label, List<int> der) {
  final encoded = base64Encode(der);
  final lines = StringBuffer('-----BEGIN $label-----\n');
  for (var i = 0; i < encoded.length; i += 64) {
    lines.writeln(encoded.substring(i, min(i + 64, encoded.length)));
  }
  lines.writeln('-----END $label-----');
  return lines.toString();
}

({String label, Uint8List bytes}) _pemBody(String pem, List<String> labels) {
  final match =
      RegExp(r'-----BEGIN ([A-Z0-9 ]+)-----([\s\S]*?)-----END \1-----')
          .firstMatch(pem);
  if (match == null) throw const FormatException('Invalid PEM');
  final label = match.group(1)!;
  if (!labels.contains(label)) {
    throw FormatException('Unsupported PEM type: $label');
  }
  final body = match.group(2)!;
  if (body.contains(':')) {
    throw const FormatException('Encrypted PEM keys are not supported');
  }
  return (
    label: label,
    bytes: base64Decode(body.replaceAll(RegExp(r'\s'), '')),
  );
}
