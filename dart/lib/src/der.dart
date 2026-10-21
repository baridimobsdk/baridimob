import 'dart:typed_data';

// Minimal DER encoder and reader, enough for RSA keys in PKCS#1 and PKCS#8.

const int derTagInteger = 0x02;
const int derTagBitString = 0x03;
const int derTagOctetString = 0x04;
const int derTagSequence = 0x30;

/// `AlgorithmIdentifier { rsaEncryption, NULL }`.
const List<int> rsaEncryptionAlgorithm = [
  0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, //
  0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
];

Uint8List derTlv(int tag, List<int> value) {
  final length = _encodeLength(value.length);
  return Uint8List(1 + length.length + value.length)
    ..[0] = tag
    ..setRange(1, 1 + length.length, length)
    ..setRange(1 + length.length, 1 + length.length + value.length, value);
}

Uint8List derSequence(List<List<int>> items) =>
    derTlv(derTagSequence, [for (final item in items) ...item]);

Uint8List derInteger(BigInt value) {
  if (value.isNegative) {
    throw ArgumentError.value(
        value, 'value', 'Negative integers are not supported');
  }
  var bytes = bigIntToBytes(value);
  if (bytes.isEmpty) bytes = Uint8List.fromList([0]);
  if (bytes[0] & 0x80 != 0) bytes = Uint8List.fromList([0, ...bytes]);
  return derTlv(derTagInteger, bytes);
}

List<int> _encodeLength(int length) {
  if (length < 0x80) return [length];
  final bytes = <int>[];
  for (var rest = length; rest > 0; rest >>= 8) {
    bytes.insert(0, rest & 0xff);
  }
  return [0x80 | bytes.length, ...bytes];
}

/// Unsigned big-endian bytes of [value], without leading zeros.
Uint8List bigIntToBytes(BigInt value) {
  final bytes = <int>[];
  for (var rest = value; rest > BigInt.zero; rest >>= 8) {
    bytes.insert(0, (rest & BigInt.from(0xff)).toInt());
  }
  return Uint8List.fromList(bytes);
}

/// Reads [bytes] as an unsigned big-endian integer.
BigInt bigIntFromBytes(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

class DerElement {
  DerElement(this.tag, this.value);

  final int tag;
  final Uint8List value;

  DerReader get children {
    if (tag != derTagSequence) {
      throw const FormatException('Expected a DER SEQUENCE');
    }
    return DerReader(value);
  }

  BigInt get integer {
    if (tag != derTagInteger || value.isEmpty) {
      throw const FormatException('Expected a DER INTEGER');
    }
    if (value[0] & 0x80 != 0) {
      throw const FormatException('Negative DER INTEGER');
    }
    return bigIntFromBytes(value);
  }
}

class DerReader {
  DerReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get isDone => _offset >= _bytes.length;

  DerElement next() {
    if (_offset + 2 > _bytes.length) {
      throw const FormatException('Truncated DER data');
    }
    final tag = _bytes[_offset++];
    var length = _bytes[_offset++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4 || _offset + count > _bytes.length) {
        throw const FormatException('Unsupported DER length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | _bytes[_offset++];
      }
    }
    if (_offset + length > _bytes.length) {
      throw const FormatException('Truncated DER data');
    }
    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return DerElement(tag, value);
  }
}
