import 'package:compliance_core/compliance_core.dart';

import 'built_in_rules.dart';
import 'masker.dart';
import 'redaction_rule.dart';
import 'sensitive_keys.dart';

/// The outcome of redacting one piece of text.
final class RedactionResult {
  /// Creates a result.
  const RedactionResult(this.text, this.counts, {this.failed = false});

  /// The redacted text. Safe to log.
  final String text;

  /// Number of values masked, per rule id.
  final Map<String, int> counts;

  /// Whether a rule threw and the text was replaced by
  /// [Redactor.failureMask].
  final bool failed;

  /// Total number of masked values.
  int get total => counts.values.fold(0, (a, b) => a + b);
}

/// Removes personal data and secrets from text and structured values.
///
/// A redactor applies [rules] in order. Text that one rule has replaced is
/// not seen by later rules, so masks are never masked twice and a value is
/// counted once.
///
/// If any rule throws, the redactor returns [failureMask] for the whole
/// input. It never falls back to the original text.
final class Redactor {
  /// Creates a redactor.
  ///
  /// * [rules]: the rule set, `BuiltInRules.defaults()` if omitted.
  /// * [customRules]: extra rules that run after [rules].
  /// * [allowlist]: exact values that are never masked, for example a public
  ///   support address.
  /// * [allowPatterns]: patterns that, when they match a whole value, keep
  ///   it unmasked.
  /// * [sensitiveKeys]: map keys whose values are always masked in
  ///   [redactValue].
  /// * [hashKey]: HMAC key for [MaskMode.hash], at least 16 bytes. Supply a
  ///   key from secure storage if hashes must be comparable across app
  ///   restarts. If omitted, a random per-process key is used.
  /// * [maxDepth]: nesting limit for [redactValue].
  /// * [maxCollectionLength]: maximum number of elements kept per list or
  ///   map in [redactValue]; the rest is replaced by [truncatedMask].
  ///
  /// When [rules] is given, [sensitiveKeys] only affects map keys in
  /// [redactValue]. Pass the same keys to `BuiltInRules.defaults` to apply
  /// them to text as well.
  ///
  /// Throws [InvalidConfigurationException] for invalid or duplicate rule
  /// ids, a short [hashKey], or a non-positive [maxDepth] or
  /// [maxCollectionLength].
  Redactor({
    List<RedactionRule>? rules,
    List<RedactionRule> customRules = const [],
    Set<String> allowlist = const {},
    List<RegExp> allowPatterns = const [],
    SensitiveKeys? sensitiveKeys,
    List<int>? hashKey,
    this.maxDepth = 16,
    this.maxCollectionLength = 1000,
  }) : rules = List.unmodifiable([
         ...rules ?? BuiltInRules.defaults(sensitiveKeys: sensitiveKeys),
         ...customRules,
       ]),
       allowlist = Set.unmodifiable(allowlist),
       allowPatterns = List.unmodifiable(allowPatterns),
       sensitiveKeys = sensitiveKeys ?? SensitiveKeys.defaults,
       _masker = Masker(hashKey: hashKey) {
    if (maxDepth <= 0 || maxCollectionLength <= 0) {
      throw const InvalidConfigurationException(
        'maxDepth and maxCollectionLength must be greater than zero.',
      );
    }
    final seen = <String>{};
    for (final rule in this.rules) {
      if (!_ruleId.hasMatch(rule.id) || rule.id.length > 48) {
        throw InvalidConfigurationException(
          'Rule id "${rule.id}" must match [a-z][a-z0-9_]* and be at most '
          '48 characters.',
        );
      }
      if (!seen.add(rule.id)) {
        throw InvalidConfigurationException('Duplicate rule id "${rule.id}".');
      }
    }
    _activeRules = this.rules.where((r) => r.enabled).toList(growable: false);
  }

  /// Replacement for an input that could not be redacted safely.
  static const String failureMask = '[REDACTED:redaction_error]';

  /// Replacement for a value under a sensitive map key.
  static const String sensitiveKeyMask = '[REDACTED:sensitive_key]';

  /// Replacement for a value nested deeper than [maxDepth].
  static const String maxDepthMask = '[REDACTED:max_depth]';

  /// Appended to a list, or used as a key, when a collection is longer than
  /// [maxCollectionLength].
  static const String truncatedMask = '[REDACTED:truncated]';

  /// Replacement for a collection that contains itself.
  static const String cycleMask = '[REDACTED:cycle]';

  /// Rule id used in counts when redaction failed.
  static const String failureRuleId = 'redaction_error';

  /// Count key used when [redactValue] cut a collection at
  /// [maxCollectionLength].
  static const String truncatedRuleId = 'truncated';

  /// Count key used when [redactValue] cut nesting at [maxDepth].
  static const String maxDepthRuleId = 'max_depth';

  static final RegExp _ruleId = RegExp(r'^[a-z][a-z0-9_]*$');

  /// All configured rules, enabled or not, in the order they run.
  final List<RedactionRule> rules;

  /// Values that are never masked.
  final Set<String> allowlist;

  /// Patterns for values that are never masked. A pattern must match the
  /// whole value.
  final List<RegExp> allowPatterns;

  /// Map keys whose values are always masked by [redactValue].
  final SensitiveKeys sensitiveKeys;

  /// Maximum nesting depth handled by [redactValue].
  final int maxDepth;

  /// Maximum number of elements kept per collection by [redactValue].
  final int maxCollectionLength;

  final Masker _masker;
  late final List<RedactionRule> _activeRules;

  /// Redacts [input].
  RedactionResult redact(String input) {
    final counts = <String, int>{};
    try {
      return RedactionResult(_redactText(input, counts), counts);
    } on Object {
      return const RedactionResult(failureMask, {
        failureRuleId: 1,
      }, failed: true);
    }
  }

  /// Redacts [value] recursively and returns a JSON-like copy.
  ///
  /// * Strings are redacted with the rules.
  /// * Integers are redacted as text and returned as a string only if a
  ///   rule matched (for example a card number stored as an `int`).
  /// * Map values under a key matched by [sensitiveKeys] are replaced by
  ///   [sensitiveKeyMask], whatever their type. Map keys are redacted as
  ///   text.
  /// * Lists, sets and other iterables become lists.
  /// * Other objects are converted with `toString()` and redacted.
  ///
  /// Per-rule counts are added to [counts] if given. If a rule throws while
  /// handling a string, that string becomes [failureMask].
  Object? redactValue(Object? value, {Map<String, int>? counts}) =>
      _redactValue(value, counts ?? <String, int>{}, 0, Set.identity());

  Object? _redactValue(
    Object? value,
    Map<String, int> counts,
    int depth,
    Set<Object> visiting,
  ) {
    switch (value) {
      case null || bool() || double():
        return value;
      case int():
        final text = value.toString();
        final redacted = _redactString(text, counts);
        return redacted == text ? value : redacted;
      case String():
        return _redactString(value, counts);
    }
    if (depth >= maxDepth) {
      counts[maxDepthRuleId] = (counts[maxDepthRuleId] ?? 0) + 1;
      return maxDepthMask;
    }
    if (value is Map || value is Iterable) {
      if (!visiting.add(value)) return cycleMask;
      try {
        if (value is Map) {
          final out = <String, Object?>{};
          var kept = 0;
          for (final entry in value.entries) {
            if (kept++ >= maxCollectionLength) {
              counts[truncatedRuleId] = (counts[truncatedRuleId] ?? 0) + 1;
              out[truncatedMask] = truncatedMask;
              break;
            }
            final key = _safeToString(entry.key, counts);
            var safeKey = key == null
                ? failureMask
                : _redactString(key, counts);
            // Distinct keys can redact to the same text; keep both values.
            if (out.containsKey(safeKey)) {
              var n = 2;
              while (out.containsKey('$safeKey#$n')) {
                n++;
              }
              safeKey = '$safeKey#$n';
            }
            if (key == null || sensitiveKeys.matches(key)) {
              out[safeKey] = sensitiveKeyMask;
              counts['sensitive_key'] = (counts['sensitive_key'] ?? 0) + 1;
            } else {
              out[safeKey] = _redactValue(
                entry.value,
                counts,
                depth + 1,
                visiting,
              );
            }
          }
          return out;
        }
        final out = <Object?>[];
        for (final item in value as Iterable<Object?>) {
          if (out.length >= maxCollectionLength) {
            counts[truncatedRuleId] = (counts[truncatedRuleId] ?? 0) + 1;
            out.add(truncatedMask);
            break;
          }
          out.add(_redactValue(item, counts, depth + 1, visiting));
        }
        return out;
      } on Object {
        // A collection whose iteration throws is dropped as a whole.
        counts[failureRuleId] = (counts[failureRuleId] ?? 0) + 1;
        return failureMask;
      } finally {
        visiting.remove(value);
      }
    }
    final text = _safeToString(value, counts);
    return text == null ? failureMask : _redactString(text, counts);
  }

  /// Calls `toString()` on [value]. Returns `null` and counts a failure if it
  /// throws, because the exception text may contain the raw value.
  String? _safeToString(Object? value, Map<String, int> counts) {
    try {
      return value.toString();
    } on Object {
      counts[failureRuleId] = (counts[failureRuleId] ?? 0) + 1;
      return null;
    }
  }

  String _redactString(String input, Map<String, int> counts) {
    final local = <String, int>{};
    try {
      final text = _redactText(input, local);
      local.forEach((k, v) => counts[k] = (counts[k] ?? 0) + v);
      return text;
    } on Object {
      counts[failureRuleId] = (counts[failureRuleId] ?? 0) + 1;
      return failureMask;
    }
  }

  String _redactText(String input, Map<String, int> counts) {
    if (input.isEmpty || _activeRules.isEmpty) return input;
    // Alternating plain and masked segments; rules only see plain segments.
    var segments = <_Segment>[_Segment(input, masked: false)];
    for (final rule in _activeRules) {
      final next = <_Segment>[];
      var changed = false;
      for (final segment in segments) {
        if (segment.masked) {
          next.add(segment);
          continue;
        }
        final spans = _accepted(rule.findSpans(segment.text), segment.text);
        if (spans.isEmpty) {
          next.add(segment);
          continue;
        }
        changed = true;
        var cursor = 0;
        for (final span in spans) {
          if (span.start > cursor) {
            next.add(
              _Segment(
                segment.text.substring(cursor, span.start),
                masked: false,
              ),
            );
          }
          next.add(
            _Segment(
              '${span.prefix}${_masker.mask(rule, span.value)}${span.suffix}',
              masked: true,
            ),
          );
          cursor = span.end;
        }
        if (cursor < segment.text.length) {
          next.add(_Segment(segment.text.substring(cursor), masked: false));
        }
        counts[rule.id] = (counts[rule.id] ?? 0) + spans.length;
      }
      if (changed) segments = next;
    }
    if (segments.length == 1) return segments.single.text;
    final buffer = StringBuffer();
    for (final segment in segments) {
      buffer.write(segment.text);
    }
    return buffer.toString();
  }

  /// Sorts spans, drops invalid, overlapping and allowlisted ones.
  List<RedactionSpan> _accepted(Iterable<RedactionSpan> found, String text) {
    final spans = found.toList();
    if (spans.isEmpty) return spans;
    for (final span in spans) {
      if (span.start < 0 ||
          span.end > text.length ||
          span.start >= span.end ||
          text.substring(span.start, span.end) !=
              '${span.prefix}${span.value}${span.suffix}') {
        throw StateError('Rule returned an inconsistent span.');
      }
    }
    spans.sort(
      (a, b) => a.start != b.start
          ? a.start.compareTo(b.start)
          : b.end.compareTo(a.end),
    );
    final result = <RedactionSpan>[];
    var lastEnd = 0;
    for (final span in spans) {
      if (span.start < lastEnd || _isAllowed(span.value)) continue;
      result.add(span);
      lastEnd = span.end;
    }
    return result;
  }

  bool _isAllowed(String value) {
    if (allowlist.contains(value)) return true;
    for (final pattern in allowPatterns) {
      final match = pattern.matchAsPrefix(value);
      if (match != null && match.end == value.length) return true;
    }
    return false;
  }
}

final class _Segment {
  _Segment(this.text, {required this.masked});

  final String text;
  final bool masked;
}
