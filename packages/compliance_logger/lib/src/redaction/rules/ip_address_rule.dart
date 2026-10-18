import '../redaction_rule.dart';

/// Masks IPv4 and IPv6 addresses. Off by default in
/// `BuiltInRules.defaults`.
///
/// IP addresses can be personal data, but they also appear in logs for
/// legitimate operational reasons and four-part version numbers such as
/// `1.2.3.4` look like IPv4 addresses. Enable this rule explicitly when it
/// fits your logs.
///
/// IPv6 candidates are validated with `Uri.parseIPv6Address`, so times such
/// as `12:30:45` are not masked.
///
/// [MaskMode.partial] keeps the first two IPv4 octets (`192.168.*.*`) or the
/// first two IPv6 groups (`2001:db8:*`).
class IpAddressRule extends RedactionRule {
  /// Creates the rule. Note that the rule is enabled by default when
  /// constructed directly; `BuiltInRules.defaults` turns it off.
  const IpAddressRule({super.enabled, super.mode}) : super(id: 'ip_address');

  // Plain digit classes are much faster than bounded quantifiers; octet
  // ranges and boundaries are checked in code.
  static final RegExp _v4 = RegExp(r'\d\d?\d?\.\d\d?\d?\.\d\d?\d?\.\d\d?\d?');
  static final RegExp _v6 = RegExp(
    r'(?=[0-9A-Fa-f:])(?<![\w:.])(?:[0-9A-Fa-f]{0,4}:){2,7}(?:[0-9A-Fa-f]{1,4}|(?:\d{1,3}\.){3}\d{1,3})?(?![\w:.])',
  );

  // Two colons with only hex digits between them, or '::'.
  static final RegExp _v6Hint = RegExp(r':[0-9A-Fa-f]{0,4}:');

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    if (input.contains('.')) {
      for (final m in _v4.allMatches(input)) {
        if (_isIPv4(input, m.start, m.end)) {
          yield RedactionSpan(start: m.start, end: m.end, value: m[0]!);
        }
      }
    }
    if (input.contains(':') && _v6Hint.hasMatch(input)) {
      for (final m in _v6.allMatches(input)) {
        final value = m[0]!;
        if (_isIPv6(value)) {
          yield RedactionSpan(start: m.start, end: m.end, value: value);
        }
      }
    }
  }

  static bool _isIPv4(String input, int start, int end) {
    if (start > 0) {
      final before = input.codeUnitAt(start - 1);
      if (before == 0x2E || _isWordChar(before)) return false;
    }
    if (end < input.length) {
      final after = input.codeUnitAt(end);
      if (_isWordChar(after)) return false;
      if (after == 0x2E &&
          end + 1 < input.length &&
          _isDigit(input.codeUnitAt(end + 1))) {
        return false;
      }
    }
    for (final octet in input.substring(start, end).split('.')) {
      if (octet.length > 1 && octet.startsWith('0')) return false;
      if (int.parse(octet) > 255) return false;
    }
    return true;
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isWordChar(int c) =>
      _isDigit(c) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F;

  static bool _isIPv6(String value) {
    if (value.length < 2) return false;
    try {
      Uri.parseIPv6Address(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  String partialMask(String value) {
    if (value.contains(':')) {
      final groups = value.split(':');
      return '${groups[0]}:${groups[1]}:*';
    }
    final octets = value.split('.');
    return '${octets[0]}.${octets[1]}.*.*';
  }
}
