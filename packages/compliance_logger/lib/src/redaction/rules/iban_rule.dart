import '../redaction_rule.dart';

/// Masks International Bank Account Numbers.
///
/// A candidate starts with a two-letter country code and two check digits,
/// may be written in groups separated by single spaces, and must have the
/// exact length registered for its country. It is only masked if the ISO
/// 13616 mod-97 checksum is valid.
///
/// [MaskMode.partial] keeps the country code and the last 4 characters:
/// `DE****3000`.
class IbanRule extends RedactionRule {
  /// Creates the rule.
  const IbanRule({super.enabled, super.mode}) : super(id: 'iban');

  /// IBAN length per country, from the SWIFT IBAN registry.
  static const Map<String, int> countryLengths = {
    'AD': 24, 'AE': 23, 'AL': 28, 'AT': 20, 'AZ': 28, 'BA': 20, 'BE': 16, //
    'BG': 22, 'BH': 22, 'BI': 27, 'BR': 29, 'BY': 28, 'CH': 21, 'CR': 22, //
    'CY': 28, 'CZ': 24, 'DE': 22, 'DJ': 27, 'DK': 18, 'DO': 28, 'EE': 20, //
    'EG': 29, 'ES': 24, 'FI': 18, 'FK': 18, 'FO': 18, 'FR': 27, 'GB': 22, //
    'GE': 22, 'GI': 23, 'GL': 18, 'GR': 27, 'GT': 28, 'HN': 28, 'HR': 21, //
    'HU': 28, 'IE': 22, 'IL': 23, 'IQ': 23, 'IS': 26, 'IT': 27, 'JO': 30, //
    'KW': 30, 'KZ': 20, 'LB': 28, 'LC': 32, 'LI': 21, 'LT': 20, 'LU': 20, //
    'LV': 21, 'LY': 25, 'MC': 27, 'MD': 24, 'ME': 22, 'MK': 19, 'MN': 20, //
    'MR': 27, 'MT': 31, 'MU': 30, 'NI': 28, 'NL': 18, 'NO': 15, 'OM': 23, //
    'PK': 24, 'PL': 28, 'PS': 29, 'PT': 25, 'QA': 29, 'RO': 24, 'RS': 22, //
    'RU': 33, 'SA': 24, 'SC': 31, 'SD': 18, 'SE': 24, 'SI': 19, 'SK': 24, //
    'SM': 27, 'SO': 23, 'ST': 25, 'SV': 28, 'TL': 23, 'TN': 24, 'TR': 26, //
    'UA': 29, 'VA': 22, 'VG': 24, 'XK': 20, 'YE': 30, //
  };

  static final RegExp _start = RegExp(r'[A-Z][A-Z]\d\d');

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    for (final m in _start.allMatches(input)) {
      if (m.start > 0 && _isAlnum(input.codeUnitAt(m.start - 1))) continue;
      final length = countryLengths[input.substring(m.start, m.start + 2)];
      if (length == null) continue;
      final end = _scan(input, m.start, length);
      if (end == null) continue;
      final raw = input.substring(m.start, end);
      if (isValidIban(raw)) {
        yield RedactionSpan(start: m.start, end: end, value: raw);
      }
    }
  }

  /// Collects [length] alphanumeric characters from [start], allowing single
  /// spaces between them. Returns the end offset, or `null` if the text does
  /// not have exactly that many characters before a boundary.
  static int? _scan(String input, int start, int length) {
    var count = 0;
    var i = start;
    while (i < input.length && count < length) {
      final c = input.codeUnitAt(i);
      if (_isAlnum(c)) {
        count++;
        i++;
      } else if (c == 0x20 &&
          count >= 4 &&
          i + 1 < input.length &&
          _isAlnum(input.codeUnitAt(i + 1))) {
        i++;
      } else {
        break;
      }
    }
    if (count != length) return null;
    if (i < input.length && _isAlnum(input.codeUnitAt(i))) return null;
    return i;
  }

  static bool _isAlnum(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A);

  @override
  String partialMask(String value) {
    final compact = value.replaceAll(' ', '');
    return '${compact.substring(0, 2)}****'
        '${compact.substring(compact.length - 4)}';
  }

  /// Whether [raw] (spaces allowed) has a registered length for its country
  /// and a valid mod-97 checksum.
  static bool isValidIban(String raw) {
    final iban = raw.replaceAll(' ', '').toUpperCase();
    if (iban.length < 5 ||
        countryLengths[iban.substring(0, 2)] != iban.length) {
      return false;
    }
    final rearranged = iban.substring(4) + iban.substring(0, 4);
    var remainder = 0;
    for (final c in rearranged.codeUnits) {
      if (c >= 0x30 && c <= 0x39) {
        remainder = (remainder * 10 + (c - 0x30)) % 97;
      } else if (c >= 0x41 && c <= 0x5A) {
        remainder = (remainder * 100 + (c - 0x41 + 10)) % 97;
      } else {
        return false;
      }
    }
    return remainder == 1;
  }
}
