import '../redaction_rule.dart';
import '../sensitive_keys.dart';

/// Masks values of sensitive fields written as text, such as passwords and
/// secrets.
///
/// Recognises these forms, where the key is checked with [SensitiveKeys]:
/// * `password=hunter2` and `password: hunter2`
/// * query strings: `?user=1&password=hunter2`
/// * JSON: `"password": "hunter2"` and `"pin": 1234`
/// * quoted values: `password='hunter 2'`
///
/// Unquoted values end at whitespace, `&`, `,`, `;`, quotes and closing
/// brackets. An unquoted value containing spaces is only masked up to the
/// first space.
///
/// [MaskMode.partial] falls back to the full mask.
class SensitiveFieldRule extends RedactionRule {
  /// Creates the rule. [keys] defaults to [SensitiveKeys.defaults].
  SensitiveFieldRule({SensitiveKeys? keys, super.enabled, super.mode})
    : keys = keys ?? SensitiveKeys.defaults,
      super(id: 'sensitive_field');

  /// Decides which keys are sensitive.
  final SensitiveKeys keys;

  static final RegExp _field = RegExp(
    r'''(?<![\w.\-])(["']?)([A-Za-z_][\w.\-]{0,63})\1\s*[:=]\s*'''
    r'''(?:"((?:[^"\\\r\n]|\\.)*)"|'((?:[^'\\\r\n]|\\.)*)'|([^\s&,;"'<>{}\[\]()]+))''',
  );

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    if (!input.contains('=') && !input.contains(':')) return;
    for (final m in _field.allMatches(input)) {
      if (!keys.matches(m[2]!)) continue;
      final whole = m[0]!;
      final quoted = m[3] ?? m[4];
      final value = quoted ?? m[5]!;
      if (value.isEmpty) continue;
      final suffix = quoted == null ? '' : whole[whole.length - 1];
      yield RedactionSpan(
        start: m.start,
        end: m.end,
        prefix: whole.substring(0, whole.length - value.length - suffix.length),
        value: value,
        suffix: suffix,
      );
    }
  }
}
