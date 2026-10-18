import '../redaction_rule.dart';
import '../sensitive_keys.dart';

/// Masks values of sensitive fields written as text, such as passwords and
/// secrets.
///
/// Recognises these forms, where the key is checked with [SensitiveKeys]:
/// * `password=hunter2`, `password: hunter2` and `password => hunter2`
/// * query strings: `?user=1&password=hunter2`
/// * JSON: `"password": "hunter2"`, `"pin": 1234`, `"password": ["x"]`
/// * quoted values: `password='hunter 2'`
/// * bracketed keys: `user[password]=hunter2`
///
/// The key is found first and the value is parsed separately, so a
/// sensitive pair inside another field's value (`Error: password=x`) is
/// still found. Value rules:
/// * a quoted value ends at the closing quote; an unterminated quote masks
///   to the end of the line;
/// * a value starting with `[` or `{` ends at the matching bracket, or the
///   end of the line;
/// * an unquoted value ends at whitespace, `&`, a quote or a closing
///   bracket. An unquoted value containing spaces is only masked up to the
///   first space.
///
/// [MaskMode.partial] falls back to the full mask.
class SensitiveFieldRule extends RedactionRule {
  /// Creates the rule. [keys] defaults to [SensitiveKeys.defaults].
  SensitiveFieldRule({SensitiveKeys? keys, super.enabled, super.mode})
    : keys = keys ?? SensitiveKeys.defaults,
      super(id: 'sensitive_field');

  /// Decides which keys are sensitive.
  final SensitiveKeys keys;

  static final RegExp _key = RegExp(
    r'''(?<![\w.\-])(["']?)([A-Za-z_][\w.\-]{0,63})\1\]?\s*(?:=>|[:=])\s*''',
  );

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    if (!input.contains('=') && !input.contains(':')) return;
    var skipUntil = 0;
    for (final k in _key.allMatches(input)) {
      if (k.start < skipUntil || !keys.matches(k[2]!)) continue;
      final value = _parseValue(input, k.end);
      if (value == null) continue;
      skipUntil = value.end;
      yield RedactionSpan(
        start: k.start,
        end: value.end,
        prefix: input.substring(k.start, value.start),
        value: input.substring(value.start, value.valueEnd),
        suffix: input.substring(value.valueEnd, value.end),
      );
    }
  }

  /// Parses the value starting at [from]. Returns `null` for an empty value.
  static ({int start, int valueEnd, int end})? _parseValue(
    String input,
    int from,
  ) {
    if (from >= input.length) return null;
    final first = input.codeUnitAt(from);
    if (first == _doubleQuote || first == _singleQuote) {
      // Up to the matching unescaped quote, or the end of the line.
      var i = from + 1;
      while (i < input.length) {
        final c = input.codeUnitAt(i);
        if (c == _backslash) {
          i += 2;
          continue;
        }
        if (c == first) {
          if (i == from + 1) return null;
          return (start: from + 1, valueEnd: i, end: i + 1);
        }
        if (c == _lf || c == _cr) break;
        i++;
      }
      final end = i > input.length ? input.length : i;
      if (end <= from + 1) return null;
      return (start: from + 1, valueEnd: end, end: end);
    }
    if (first == _openBracket || first == _openBrace) {
      // Up to the matching close, or the end of the line.
      var depth = 0;
      var i = from;
      while (i < input.length) {
        final c = input.codeUnitAt(i);
        if (c == _openBracket || c == _openBrace) depth++;
        if (c == _closeBracket || c == _closeBrace) {
          depth--;
          if (depth == 0) return (start: from, valueEnd: i + 1, end: i + 1);
        }
        if (c == _lf || c == _cr) break;
        i++;
      }
      return (start: from, valueEnd: i, end: i);
    }
    var i = from;
    while (i < input.length && !_endsBareValue(input.codeUnitAt(i))) {
      i++;
    }
    if (i == from) return null;
    return (start: from, valueEnd: i, end: i);
  }

  static const int _doubleQuote = 0x22;
  static const int _singleQuote = 0x27;
  static const int _backslash = 0x5C;
  static const int _lf = 0x0A;
  static const int _cr = 0x0D;
  static const int _openBracket = 0x5B;
  static const int _closeBracket = 0x5D;
  static const int _openBrace = 0x7B;
  static const int _closeBrace = 0x7D;

  static bool _endsBareValue(int c) =>
      c == 0x20 || // space
      c == 0x09 || // tab
      c == _lf ||
      c == _cr ||
      c == 0x26 || // &
      c == _doubleQuote ||
      c == _singleQuote ||
      c == _closeBracket ||
      c == _closeBrace ||
      c == 0x29 || // )
      c == 0x3E; // >
}
