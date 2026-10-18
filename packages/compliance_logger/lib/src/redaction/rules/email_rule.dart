import '../redaction_rule.dart';

/// Masks email addresses, including internationalised addresses
/// (`jäne@exämple.com`) and URL-encoded ones (`jane%40example.com`).
///
/// [MaskMode.partial] keeps the first character of the local part and the
/// domain: `j***@example.com`. The domain can itself identify a person or a
/// small organisation, so prefer [MaskMode.full] or [MaskMode.hash] unless
/// the domain is needed.
class EmailRule extends RedactionRule {
  /// Creates the rule.
  const EmailRule({super.enabled, super.mode}) : super(id: 'email');

  static final RegExp _email = RegExp(
    r'(?<![\p{L}\p{N}._%+\-])[\p{L}\p{N}._%+\-]+(?:@|%40)[\p{L}\p{N}\-]+(?:\.[\p{L}\p{N}\-]+)*\.\p{L}{2,}(?![\p{L}\p{N}])',
    unicode: true,
  );
  static final RegExp _encodedAt = RegExp('%40');

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    if (!input.contains('@') && !_encodedAt.hasMatch(input)) return;
    for (final m in _email.allMatches(input)) {
      yield RedactionSpan(start: m.start, end: m.end, value: m[0]!);
    }
  }

  @override
  String partialMask(String value) {
    final at = value.lastIndexOf('@');
    if (at >= 0) return '${value[0]}***${value.substring(at)}';
    final encoded = value.lastIndexOf('%40');
    return '${value[0]}***@${value.substring(encoded + 3)}';
  }
}
