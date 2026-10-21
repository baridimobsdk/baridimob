import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'keys.dart';

/// Placeholder value of the `stamp` field while the request is being signed.
const String initialStamp = '00000000000000000000';

/// Encodes [params] as a form body (or query string) and signs it.
///
/// The `stamp` field is appended with [initialStamp], the whole string is
/// signed with RSA-SHA1, then the placeholder is replaced by the signature.
String signParams(Map<String, String> params, String privateKeyPem) =>
    _sign(params, privateKeyPem, formEncode);

/// Same as [signParams], for a URL query string.
///
/// Dart's [Uri] decodes `%7E` back to `~`, so the query is signed in the exact
/// form that is sent; otherwise the server would see a different string.
String signQuery(Map<String, String> params, String privateKeyPem) => _sign(
    params, privateKeyPem, (value) => formEncode(value).replaceAll('%7E', '~'));

String _sign(
  Map<String, String> params,
  String privateKeyPem,
  String Function(String) encode,
) {
  final withPlaceholder = {...params, 'stamp': initialStamp};
  final unsigned = withPlaceholder.entries
      .map((entry) => '${encode(entry.key)}=${encode(entry.value)}')
      .join('&');
  final signature = _rsaSha1Hex(unsigned, privateKeyPem);
  return unsigned.replaceFirst('stamp=$initialStamp', 'stamp=$signature');
}

/// Encodes [body] as JSON and signs it, with the same placeholder rule as
/// [signParams].
String signJsonBody(Map<String, Object?> body, String privateKeyPem) {
  final withPlaceholder = {
    ...normalizeJson(body) as Map<String, Object?>,
    'stamp': initialStamp
  };
  final unsigned = jsonEncode(withPlaceholder);
  final signature = _rsaSha1Hex(unsigned, privateKeyPem);
  return unsigned.replaceFirst(
    '"stamp":"$initialStamp"',
    '"stamp":"$signature"',
  );
}

/// `application/x-www-form-urlencoded` encoding, byte-for-byte identical to
/// the WHATWG URL standard (and therefore to the TypeScript SDK).
String formEncode(String value) {
  final buffer = StringBuffer();
  for (final byte in utf8.encode(value)) {
    if (byte == 0x20) {
      buffer.write('+');
    } else if ((byte >= 0x30 && byte <= 0x39) ||
        (byte >= 0x41 && byte <= 0x5a) ||
        (byte >= 0x61 && byte <= 0x7a) ||
        byte == 0x2a ||
        byte == 0x2d ||
        byte == 0x2e ||
        byte == 0x5f) {
      buffer.writeCharCode(byte);
    } else {
      buffer
        ..write('%')
        ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return buffer.toString();
}

/// Makes Dart JSON output match JavaScript's `JSON.stringify` for numbers:
/// `1.0` becomes `1`, and non-finite numbers become `null`.
Object? normalizeJson(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        '${entry.key}': normalizeJson(entry.value),
    };
  }
  if (value is List) return [for (final item in value) normalizeJson(item)];
  if (value is double) {
    if (!value.isFinite) return null;
    if (value == value.truncateToDouble() && value.abs() < 1e21) {
      return value.toInt();
    }
  }
  return value;
}

String? _cachedPem;
RSAPrivateKey? _cachedKey;

String _rsaSha1Hex(String payload, String privateKeyPem) {
  if (_cachedPem != privateKeyPem) {
    _cachedKey = RsaKey.fromPem(privateKeyPem).toPointyCastle();
    _cachedPem = privateKeyPem;
  }
  final signer = RSASigner(SHA1Digest(), '06052b0e03021a')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(_cachedKey!));
  final signature =
      signer.generateSignature(Uint8List.fromList(utf8.encode(payload)));
  final buffer = StringBuffer();
  for (final byte in signature.bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
