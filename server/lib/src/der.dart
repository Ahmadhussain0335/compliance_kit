import 'dart:typed_data';

/// A DER-encoded ASN.1 element (tag, length, value).
///
/// Only what is needed to read X.509 certificates is supported: definite
/// lengths and single-byte tags.
final class Der {
  Der._(this._bytes, this.tag, this.start, this.valueStart, this.end);

  /// Parses the element that starts at [offset] in [bytes].
  ///
  /// Throws [FormatException] for truncated or unsupported encodings.
  factory Der.parse(Uint8List bytes, [int offset = 0]) {
    if (offset + 2 > bytes.length) {
      throw const FormatException('DER: truncated header');
    }
    final tag = bytes[offset];
    if (tag & 0x1F == 0x1F) {
      throw const FormatException('DER: multi-byte tags are not supported');
    }
    var pos = offset + 1;
    var length = bytes[pos++];
    if (length & 0x80 != 0) {
      final count = length & 0x7F;
      if (count == 0 || count > 4) {
        throw const FormatException('DER: unsupported length encoding');
      }
      if (pos + count > bytes.length) {
        throw const FormatException('DER: truncated length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[pos++];
      }
    }
    final end = pos + length;
    if (end > bytes.length) {
      throw const FormatException('DER: value exceeds input');
    }
    return Der._(bytes, tag, offset, pos, end);
  }

  final Uint8List _bytes;

  /// The tag byte, for example `0x30` for SEQUENCE.
  final int tag;

  /// Offset of the tag byte.
  final int start;

  /// Offset of the first value byte.
  final int valueStart;

  /// Offset after the last value byte.
  final int end;

  /// Tag of SEQUENCE.
  static const int sequence = 0x30;

  /// Tag of SET.
  static const int set = 0x31;

  /// Tag of INTEGER.
  static const int integer = 0x02;

  /// Tag of BIT STRING.
  static const int bitString = 0x03;

  /// Tag of OCTET STRING.
  static const int octetString = 0x04;

  /// Tag of OBJECT IDENTIFIER.
  static const int objectIdentifier = 0x06;

  /// Tag of UTCTime.
  static const int utcTime = 0x17;

  /// Tag of GeneralizedTime.
  static const int generalizedTime = 0x18;

  /// The value bytes.
  Uint8List get value => Uint8List.sublistView(_bytes, valueStart, end);

  /// The complete encoding, header included.
  Uint8List get encoded => Uint8List.sublistView(_bytes, start, end);

  /// Child elements of a constructed element.
  List<Der> get children {
    final result = <Der>[];
    var pos = valueStart;
    while (pos < end) {
      final child = Der.parse(_bytes, pos);
      if (child.end > end) {
        throw const FormatException('DER: child exceeds parent');
      }
      result.add(child);
      pos = child.end;
    }
    return result;
  }

  /// Returns this element after checking its tag.
  Der expect(int expectedTag) {
    if (tag != expectedTag) {
      throw FormatException(
        'DER: expected tag 0x${expectedTag.toRadixString(16)}, '
        'got 0x${tag.toRadixString(16)}',
      );
    }
    return this;
  }

  /// Decodes an OBJECT IDENTIFIER value as dotted text.
  String get oid {
    expect(objectIdentifier);
    final v = value;
    if (v.isEmpty) throw const FormatException('DER: empty OID');
    final parts = <int>[v[0] ~/ 40, v[0] % 40];
    var acc = 0;
    for (var i = 1; i < v.length; i++) {
      acc = (acc << 7) | (v[i] & 0x7F);
      if (v[i] & 0x80 == 0) {
        parts.add(acc);
        acc = 0;
      }
    }
    return parts.join('.');
  }

  /// Decodes an unsigned INTEGER value.
  BigInt get unsignedInteger {
    expect(integer);
    var result = BigInt.zero;
    for (final b in value) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  /// The content of a BIT STRING without the unused-bits byte.
  Uint8List get bitStringBytes {
    expect(bitString);
    final v = value;
    if (v.isEmpty || v[0] != 0) {
      throw const FormatException('DER: unsupported BIT STRING padding');
    }
    return Uint8List.sublistView(v, 1);
  }

  /// Decodes a UTCTime or GeneralizedTime value in UTC.
  DateTime get time {
    final text = String.fromCharCodes(value);
    final String full;
    if (tag == utcTime) {
      final year = int.parse(text.substring(0, 2));
      full = '${year >= 50 ? 19 : 20}$text';
    } else {
      expect(generalizedTime);
      full = text;
    }
    if (!full.endsWith('Z') || full.length != 15) {
      throw const FormatException('DER: unsupported time format');
    }
    return DateTime.utc(
      int.parse(full.substring(0, 4)),
      int.parse(full.substring(4, 6)),
      int.parse(full.substring(6, 8)),
      int.parse(full.substring(8, 10)),
      int.parse(full.substring(10, 12)),
      int.parse(full.substring(12, 14)),
    );
  }
}
