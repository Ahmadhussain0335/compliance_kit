import '../redaction_rule.dart';

/// Masks phone numbers.
///
/// By default only international numbers are matched: a `+` or `00`
/// prefix followed by 8 to 15 digits (the E.164 maximum), with optional
/// single spaces, dots, dashes or slashes and parentheses around groups,
/// for example `+49 176 1234 5678`, `+1 (555) 123-4567` or
/// `0044 20 7946 0958`.
///
/// Set [matchNational] to also match national formats that start with a
/// trunk `0` or a parenthesised area code, such as `030 1234567` or
/// `(555) 123-4567`. National matching has more false positives and is off
/// by default.
///
/// Numbers that touch letters, dots, colons or slashes are ignored, so
/// versions, dates, times and URLs are not masked.
///
/// [MaskMode.partial] keeps the first 3 and last 2 characters:
/// `+49*******78`.
class PhoneRule extends RedactionRule {
  /// Creates the rule.
  const PhoneRule({super.enabled, super.mode, this.matchNational = false})
    : super(id: 'phone');

  /// Whether national formats without a country code are matched.
  final bool matchNational;

  static final RegExp _international = RegExp(
    r'(?<![\w+.\-])(?:\+|(?<![:/])(?<!\d[ .\-/])00) ?\(?[1-9]\)?(?:[ .\-/]?\(?\d\)?){7,14}(?![\w+]|[.:/\-]\d)',
  );
  static final RegExp _national = RegExp(
    r'(?<![\w+.:/\-])(?<!\d[ .\-/])(?:\(\d{2,5}\) ?|0\d{2,4}[ .\-/]?)\d{3,4}[ .\-]?\d{3,5}(?![\w+]|[.:/\-]\d)',
  );
  static final RegExp _nonDigit = RegExp(r'\D');
  static final RegExp _nonPhoneChar = RegExp(r'[^\d+]');

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    for (final m in _international.allMatches(input)) {
      final raw = m[0]!;
      if (_balancedParens(raw)) {
        yield RedactionSpan(start: m.start, end: m.end, value: raw);
      }
    }
    if (!matchNational) return;
    for (final m in _national.allMatches(input)) {
      final raw = m[0]!;
      final digits = raw.replaceAll(_nonDigit, '').length;
      if (digits >= 7 && digits <= 13 && _balancedParens(raw)) {
        yield RedactionSpan(start: m.start, end: m.end, value: raw);
      }
    }
  }

  static bool _balancedParens(String raw) {
    var depth = 0;
    for (final c in raw.codeUnits) {
      if (c == 0x28) depth++;
      if (c == 0x29) depth--;
      if (depth < 0 || depth > 1) return false;
    }
    return depth == 0;
  }

  @override
  String partialMask(String value) {
    final compact = value.replaceAll(_nonPhoneChar, '');
    if (compact.length < 6) return fullMask;
    return '${compact.substring(0, 3)}'
        '${'*' * (compact.length - 5)}'
        '${compact.substring(compact.length - 2)}';
  }
}
