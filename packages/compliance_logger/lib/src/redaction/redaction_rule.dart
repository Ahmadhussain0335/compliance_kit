/// How a rule replaces a sensitive value.
enum MaskMode {
  /// Keeps a small, rule-specific part of the value so it stays
  /// recognisable, for example `j***@example.com` or `****1234`.
  ///
  /// Rules for which a partial value makes no sense (passwords, bearer
  /// tokens) fall back to [full].
  partial,

  /// Replaces the value with `[REDACTED:<rule id>]`.
  full,

  /// Replaces the value with `[HASH:<rule id>:<12 hex chars>]`, a keyed
  /// HMAC-SHA-256 prefix. The same value produces the same output for the
  /// same key, so log lines can be correlated without revealing the value.
  hash,
}

/// Enable flag and mask mode for a rule.
///
/// Used to configure built-in rules, see `BuiltInRules.defaults`.
final class RuleSettings {
  /// Creates rule settings.
  const RuleSettings({this.enabled = true, this.mode = MaskMode.full});

  /// Settings for a rule that is turned off.
  static const RuleSettings disabled = RuleSettings(enabled: false);

  /// Whether the rule runs.
  final bool enabled;

  /// How matched values are replaced.
  final MaskMode mode;
}

/// A sensitive value found by a [RedactionRule].
///
/// The span covers `input.substring(start, end)`, which must equal
/// `prefix + value + suffix`. Only [value] is masked; [prefix] and [suffix]
/// are kept as they are. This lets a rule keep context such as the key in
/// `password=hunter2` while masking only the secret.
final class RedactionSpan {
  /// Creates a span. [prefix] and [suffix] default to empty.
  const RedactionSpan({
    required this.start,
    required this.end,
    required this.value,
    this.prefix = '',
    this.suffix = '',
  });

  /// Start offset in the input, inclusive.
  final int start;

  /// End offset in the input, exclusive.
  final int end;

  /// Text kept before the masked value.
  final String prefix;

  /// The sensitive value to mask.
  final String value;

  /// Text kept after the masked value.
  final String suffix;
}

/// A rule that finds one kind of sensitive value in text.
///
/// Subclass this for full control, or use `RegexRedactionRule` and
/// `FunctionRedactionRule` for custom rules.
abstract class RedactionRule {
  /// Creates a rule.
  ///
  /// [id] must be a lowercase identifier (`[a-z][a-z0-9_]*`). It appears in
  /// masked output and in audit events, so it must not contain personal data.
  const RedactionRule({
    required this.id,
    this.enabled = true,
    this.mode = MaskMode.full,
  });

  /// Identifier used in masked output, for example `email`.
  final String id;

  /// Whether this rule runs.
  final bool enabled;

  /// How matched values are replaced.
  final MaskMode mode;

  /// Returns the sensitive values in [input].
  ///
  /// Spans may be returned in any order. Overlapping spans are resolved by
  /// the redactor, which keeps the earliest and then the longest span.
  Iterable<RedactionSpan> findSpans(String input);

  /// Returns the [MaskMode.partial] form of [value].
  ///
  /// The default returns the full mask, which is the safe choice for rules
  /// where any visible part would leak information.
  String partialMask(String value) => fullMask;

  /// The [MaskMode.full] replacement, `[REDACTED:<id>]`.
  String get fullMask => '[REDACTED:$id]';
}

/// A custom rule that matches a regular expression.
///
/// By default the whole match is masked. To keep context around the
/// sensitive part, use the named groups `prefix`, `value` and `suffix`, which
/// must together cover the whole match in that order:
///
/// ```dart
/// RegexRedactionRule(
///   id: 'employee_id',
///   pattern: RegExp(r'(?<prefix>emp=)(?<value>\d{6})'),
/// );
/// ```
///
/// If the named groups do not cover the whole match exactly, the whole match
/// is masked, so a mistake in the pattern masks more rather than less.
class RegexRedactionRule extends RedactionRule {
  /// Creates a regex rule. If [validator] is given, a match is only masked
  /// when the validator returns `true` for its value.
  const RegexRedactionRule({
    required super.id,
    required this.pattern,
    this.validator,
    String Function(String value)? partial,
    super.enabled,
    super.mode,
  }) : _partial = partial;

  /// The pattern to search for.
  final RegExp pattern;

  /// Optional check that filters out false positives.
  final bool Function(String value)? validator;

  final String Function(String value)? _partial;

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    for (final match in pattern.allMatches(input)) {
      if (match.end == match.start) continue;
      final span = spanFromMatch(match);
      final check = validator;
      if (check != null && !check(span.value)) continue;
      yield span;
    }
  }

  @override
  String partialMask(String value) =>
      _partial == null ? fullMask : _partial(value);

  /// Builds a span from [match] using the optional `prefix`, `value` and
  /// `suffix` named groups.
  static RedactionSpan spanFromMatch(RegExpMatch match) {
    final whole = match[0]!;
    final names = match.groupNames;
    if (names.contains('value')) {
      final prefix = names.contains('prefix')
          ? match.namedGroup('prefix') ?? ''
          : '';
      final value = match.namedGroup('value') ?? '';
      final suffix = names.contains('suffix')
          ? match.namedGroup('suffix') ?? ''
          : '';
      if (value.isNotEmpty && '$prefix$value$suffix' == whole) {
        return RedactionSpan(
          start: match.start,
          end: match.end,
          prefix: prefix,
          value: value,
          suffix: suffix,
        );
      }
    }
    return RedactionSpan(start: match.start, end: match.end, value: whole);
  }
}

/// A custom rule backed by a function that finds sensitive values.
///
/// ```dart
/// FunctionRedactionRule(
///   id: 'customer_number',
///   find: (input) => myParser.findCustomerNumbers(input),
/// );
/// ```
class FunctionRedactionRule extends RedactionRule {
  /// Creates a function rule.
  const FunctionRedactionRule({
    required super.id,
    required Iterable<RedactionSpan> Function(String input) find,
    String Function(String value)? partial,
    super.enabled,
    super.mode,
  }) : _find = find,
       _partial = partial;

  final Iterable<RedactionSpan> Function(String input) _find;
  final String Function(String value)? _partial;

  @override
  Iterable<RedactionSpan> findSpans(String input) => _find(input);

  @override
  String partialMask(String value) =>
      _partial == null ? fullMask : _partial(value);
}
