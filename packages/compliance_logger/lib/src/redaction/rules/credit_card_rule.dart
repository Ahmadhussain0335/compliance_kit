import '../redaction_rule.dart';

/// Masks payment card numbers.
///
/// A candidate is 13 to 19 digits, optionally grouped with single spaces or
/// dashes (one separator style per number). It is only masked if it starts
/// with a known card network prefix (Visa, Mastercard, American Express,
/// Discover, JCB, Diners Club, UnionPay, Maestro) and passes the Luhn check.
/// Digits that are part of a longer number, a decimal or a dotted version
/// are ignored.
///
/// Random 16-digit numbers with a valid prefix pass the Luhn check about one
/// time in ten, so an order id can occasionally be masked. That is the safe
/// direction for a logger.
///
/// [MaskMode.partial] keeps the last 4 digits: `****1234`.
class CreditCardRule extends RedactionRule {
  /// Creates the rule.
  const CreditCardRule({super.enabled, super.mode}) : super(id: 'credit_card');

  static final RegExp _candidate = RegExp(
    r'(?<![\w.+\-/:])\d(?:[ \-]?\d){12,18}(?![\w\-/:]|\.\d)',
  );
  static final RegExp _hint = RegExp(r'\d\d\d\d');
  static final RegExp _separators = RegExp(r'[ \-]');

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    if (!_hint.hasMatch(input)) return;
    for (final m in _candidate.allMatches(input)) {
      final raw = m[0]!;
      if (isCardNumber(raw)) {
        yield RedactionSpan(start: m.start, end: m.end, value: raw);
      }
    }
  }

  @override
  String partialMask(String value) {
    final digits = value.replaceAll(_separators, '');
    return '****${digits.substring(digits.length - 4)}';
  }

  /// Whether [raw] is a plausible card number: consistent separators, a
  /// known network prefix and a valid Luhn checksum.
  static bool isCardNumber(String raw) {
    final hasSpace = raw.contains(' ');
    final hasDash = raw.contains('-');
    if (hasSpace && hasDash) return false;
    final digits = raw.replaceAll(_separators, '');
    if (digits.length < 13 || digits.length > 19) return false;
    return hasKnownPrefix(digits) && luhnValid(digits);
  }

  /// Whether [digits] starts with a known card network prefix.
  static bool hasKnownPrefix(String digits) {
    int prefix(int length) => int.parse(digits.substring(0, length));
    final p2 = prefix(2);
    final p3 = prefix(3);
    final p4 = prefix(4);
    final p6 = prefix(6);
    return digits.startsWith('4') ||
        (p2 >= 51 && p2 <= 55) ||
        (p4 >= 2221 && p4 <= 2720) ||
        p2 == 34 ||
        p2 == 37 ||
        p4 == 6011 ||
        p2 == 65 ||
        (p3 >= 644 && p3 <= 649) ||
        (p6 >= 622126 && p6 <= 622925) ||
        (p4 >= 3528 && p4 <= 3589) ||
        p2 == 36 ||
        p2 == 38 ||
        p2 == 39 ||
        (p3 >= 300 && p3 <= 305) ||
        p2 == 62 ||
        p2 == 50 ||
        (p2 >= 56 && p2 <= 58) ||
        p2 == 63 ||
        p2 == 67;
  }

  /// Whether [digits] passes the Luhn checksum.
  static bool luhnValid(String digits) {
    var sum = 0;
    var doubleIt = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var d = digits.codeUnitAt(i) - 0x30;
      if (doubleIt) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      doubleIt = !doubleIt;
    }
    return sum % 10 == 0;
  }
}
