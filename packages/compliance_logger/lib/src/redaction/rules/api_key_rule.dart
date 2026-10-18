import 'dart:math' as math;

import '../redaction_rule.dart';

/// Masks API keys and other credentials with a recognisable shape.
///
/// Known formats:
/// * AWS access key ids (`AKIA...`, `ASIA...` and related prefixes)
/// * Google API keys (`AIza...`)
/// * GitHub tokens (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`, `github_pat_`)
/// * Stripe secret and restricted keys (`sk_live_`, `rk_test_`, ...)
/// * Slack tokens (`xoxb-`, `xoxp-`, ...)
/// * `sk-` prefixed keys used by several AI providers
/// * PEM private key blocks
///
/// Generic keys: any run of 32 or more characters from `[A-Za-z0-9+/_-]`
/// that contains upper case, lower case and digits and has a Shannon entropy
/// of at least [minEntropy] bits per character. This deliberately skips
/// UUIDs and hex digests (no mixed case) and ordinary identifiers (low
/// entropy).
///
/// [MaskMode.partial] keeps the first 4 characters.
class ApiKeyRule extends RedactionRule {
  /// Creates the rule.
  const ApiKeyRule({super.enabled, super.mode, this.minEntropy = 4.0})
    : super(id: 'api_key');

  /// Minimum Shannon entropy, in bits per character, for a generic key.
  final double minEntropy;

  static final RegExp _pemHint = RegExp('PRIVATE KEY-----');
  static final RegExp _pem = RegExp(
    r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
  );

  // Known formats, matched against runs of [A-Za-z0-9+/_-] found by the
  // linear scan in findSpans. Each must match the start of a run.
  static final List<RegExp> _known = [
    RegExp(
      r'(?:AKIA|ASIA|ABIA|ACCA|AGPA|AIDA|AROA|ANPA|ANVA|AIPA)[A-Z0-9]{16}(?![A-Za-z0-9])',
    ),
    RegExp(r'AIza[0-9A-Za-z_\-]{35}(?![A-Za-z0-9_\-])'),
    RegExp(r'(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,255}'),
    RegExp(r'github_pat_[A-Za-z0-9_]{22,255}'),
    RegExp(r'(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}'),
    RegExp(r'xox[abposr]-[A-Za-z0-9\-]{10,}'),
    RegExp(r'sk-[A-Za-z0-9_\-]{20,}'),
  ];

  /// Shortest run that can hold a known-format key.
  static const int _minKnownLength = 14;

  /// Minimum length of a generic key candidate.
  static const int _minGenericLength = 32;

  static final RegExp _upper = RegExp('[A-Z]');
  static final RegExp _lower = RegExp('[a-z]');
  static final RegExp _digit = RegExp('[0-9]');

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    var pemEnd = 0;
    if (_pemHint.hasMatch(input)) {
      for (final m in _pem.allMatches(input)) {
        yield RedactionSpan(start: m.start, end: m.end, value: m[0]!);
        pemEnd = m.end;
      }
    }
    if (input.length < _minKnownLength) return;
    // Linear scan for runs of [A-Za-z0-9+/_-] followed by up to two '='.
    var i = 0;
    while (i < input.length) {
      if (!_isKeyChar(input.codeUnitAt(i))) {
        i++;
        continue;
      }
      final start = i;
      while (i < input.length && _isKeyChar(input.codeUnitAt(i))) {
        i++;
      }
      var end = i;
      var padding = 0;
      while (end < input.length &&
          input.codeUnitAt(end) == 0x3D &&
          padding < 2) {
        end++;
        padding++;
      }
      final bodyLength = i - start;
      if (bodyLength < _minKnownLength || start < pemEnd) {
        i = end;
        continue;
      }
      final known = _matchKnown(input.substring(start, i));
      if (known != null) {
        yield RedactionSpan(
          start: start,
          end: start + known.length,
          value: known,
        );
        i = end;
        continue;
      }
      final followedByPadding =
          end < input.length && input.codeUnitAt(end) == 0x3D;
      final precededByPadding =
          start > 0 && input.codeUnitAt(start - 1) == 0x3D;
      if (bodyLength >= _minGenericLength &&
          !followedByPadding &&
          !precededByPadding) {
        final value = input.substring(start, end);
        if (isHighEntropyKey(value, minEntropy)) {
          yield RedactionSpan(start: start, end: end, value: value);
        }
      }
      i = end;
    }
  }

  static String? _matchKnown(String run) {
    for (final pattern in _known) {
      final m = pattern.matchAsPrefix(run);
      if (m != null) return m[0];
    }
    return null;
  }

  static bool _isKeyChar(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x2B ||
      c == 0x2F ||
      c == 0x5F ||
      c == 0x2D;

  @override
  String partialMask(String value) => value.startsWith('-----BEGIN')
      ? fullMask
      : '${value.substring(0, 4)}****';

  /// Whether [value] has mixed case, digits and at least [minEntropy] bits
  /// of Shannon entropy per character.
  static bool isHighEntropyKey(String value, double minEntropy) =>
      _upper.hasMatch(value) &&
      _lower.hasMatch(value) &&
      _digit.hasMatch(value) &&
      shannonEntropy(value) >= minEntropy;

  /// Shannon entropy of [value] in bits per character.
  static double shannonEntropy(String value) {
    if (value.isEmpty) return 0;
    final counts = <int, int>{};
    for (final unit in value.codeUnits) {
      counts[unit] = (counts[unit] ?? 0) + 1;
    }
    var entropy = 0.0;
    for (final count in counts.values) {
      final p = count / value.length;
      entropy -= p * math.log(p) / math.ln2;
    }
    return entropy;
  }
}
