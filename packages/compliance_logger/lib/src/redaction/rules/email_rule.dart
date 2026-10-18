import '../redaction_rule.dart';

/// Masks email addresses.
///
/// [MaskMode.partial] keeps the first character of the local part and the
/// domain: `j***@example.com`. The domain can itself identify a person or a
/// small organisation, so prefer [MaskMode.full] or [MaskMode.hash] unless
/// the domain is needed.
class EmailRule extends RedactionRule {
  /// Creates the rule.
  const EmailRule({super.enabled, super.mode}) : super(id: 'email');

  static final RegExp _email = RegExp(
    r'(?<![A-Za-z0-9._%+\-])[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}(?![A-Za-z0-9\-])',
  );

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    if (!input.contains('@')) return;
    for (final m in _email.allMatches(input)) {
      yield RedactionSpan(start: m.start, end: m.end, value: m[0]!);
    }
  }

  @override
  String partialMask(String value) {
    final at = value.lastIndexOf('@');
    return '${value[0]}***${value.substring(at)}';
  }
}
