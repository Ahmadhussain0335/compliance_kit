import '../redaction_rule.dart';

/// Masks JSON Web Tokens (`eyJ<header>.eyJ<payload>.<signature>`).
///
/// [MaskMode.partial] keeps the header segment, which describes the
/// algorithm and key id, and masks the payload and signature.
class JwtRule extends RedactionRule {
  /// Creates the rule.
  const JwtRule({super.enabled, super.mode}) : super(id: 'jwt');

  static final RegExp _jwt = RegExp(
    r'(?<![A-Za-z0-9_\-])eyJ[A-Za-z0-9_\-]{5,}\.eyJ[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]*',
  );

  static final RegExp _hint = RegExp('eyJ');

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    if (!_hint.hasMatch(input)) return;
    for (final m in _jwt.allMatches(input)) {
      yield RedactionSpan(start: m.start, end: m.end, value: m[0]!);
    }
  }

  @override
  String partialMask(String value) =>
      '${value.substring(0, value.indexOf('.'))}.$fullMask';
}
