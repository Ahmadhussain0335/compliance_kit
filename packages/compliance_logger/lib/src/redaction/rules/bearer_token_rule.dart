import 'dart:convert';

import '../redaction_rule.dart';

/// Masks `Authorization` header values and `Bearer` / `Basic` credentials.
///
/// Matches:
/// * `Authorization: <value>` and the JSON form `"authorization": "<value>"`.
///   The whole value is masked, including the scheme: up to the closing
///   quote if the value is quoted, otherwise up to the end of the line. If
///   the line holds only the scheme (`Authorization: Bearer` with the token
///   on the next line), the next token is masked too.
/// * `Bearer <token>` where the token is at least 20 characters, or at
///   least 8 characters containing a digit or one of `-._~+/=`. This skips
///   prose such as "Bearer authentication".
/// * `Basic <credentials>` where the credentials are base64 that decodes to
///   `user:password`.
///
/// [MaskMode.partial] falls back to the full mask.
class BearerTokenRule extends RedactionRule {
  /// Creates the rule.
  const BearerTokenRule({super.enabled, super.mode})
    : super(id: 'bearer_token');

  static final RegExp _header = RegExp(
    r'''authorization["']?\s*[:=][ \t]*(["']?)''',
    caseSensitive: false,
  );
  static final RegExp _schemeOnly = RegExp(
    r'^(?:bearer|basic|digest|token|negotiate|ntlm)$',
    caseSensitive: false,
  );
  static final RegExp _nextToken = RegExp(r'\s*\S+');
  static final RegExp _bearer = RegExp(
    r'\b(bearer\s+)([A-Za-z0-9\-._~+/]{8,}=*)',
    caseSensitive: false,
  );
  static final RegExp _basic = RegExp(
    r'\b(basic\s+)([A-Za-z0-9+/]{4,}={0,2})(?![A-Za-z0-9+/=])',
    caseSensitive: false,
  );
  // Separate literal patterns are much faster than one alternation.
  static final List<RegExp> _hints = [
    RegExp('authorization', caseSensitive: false),
    RegExp('bearer', caseSensitive: false),
    RegExp('basic', caseSensitive: false),
  ];
  static final RegExp _tokenMarker = RegExp(r'[0-9\-._~+/=]');

  @override
  Iterable<RedactionSpan> findSpans(String input) sync* {
    if (!_hints.any((h) => h.hasMatch(input))) return;
    for (final m in _header.allMatches(input)) {
      final span = _headerSpan(input, m);
      if (span != null) yield span;
    }
    for (final m in _bearer.allMatches(input)) {
      final token = m[2]!;
      if (token.length < 20 && !_tokenMarker.hasMatch(token)) continue;
      yield RedactionSpan(
        start: m.start,
        end: m.end,
        prefix: m[1]!,
        value: token,
      );
    }
    for (final m in _basic.allMatches(input)) {
      if (!_isBasicCredential(m[2]!)) continue;
      yield RedactionSpan(
        start: m.start,
        end: m.end,
        prefix: m[1]!,
        value: m[2]!,
      );
    }
  }

  static RedactionSpan? _headerSpan(String input, RegExpMatch m) {
    final quote = m[1]!;
    final valueStart = m.end;
    var end = valueStart;
    if (quote.isNotEmpty) {
      while (end < input.length &&
          input[end] != quote &&
          input[end] != '\n' &&
          input[end] != '\r') {
        end++;
      }
    } else {
      while (end < input.length && input[end] != '\n' && input[end] != '\r') {
        end++;
      }
      while (end > valueStart && input[end - 1].trim().isEmpty) {
        end--;
      }
      if (_schemeOnly.hasMatch(input.substring(valueStart, end))) {
        final next = _nextToken.matchAsPrefix(input, end);
        if (next != null) end = next.end;
      }
    }
    if (end == valueStart) return null;
    return RedactionSpan(
      start: m.start,
      end: end,
      prefix: input.substring(m.start, valueStart),
      value: input.substring(valueStart, end),
    );
  }

  static bool _isBasicCredential(String encoded) {
    try {
      return utf8
          .decode(base64.decode(base64.normalize(encoded)))
          .contains(':');
    } on FormatException {
      return false;
    }
  }
}
