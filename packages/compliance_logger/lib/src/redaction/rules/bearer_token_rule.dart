import 'dart:convert';

import '../redaction_rule.dart';

/// Masks `Authorization` header values and `Bearer` / `Basic` credentials.
///
/// Matches:
/// * `Authorization: <anything up to end of line>` and the JSON form
///   `"authorization": "<value>"`. The whole value is masked, including the
///   scheme.
/// * `Bearer <token>` where the token is at least 8 characters and contains
///   a digit or one of `-._~+/=`, which skips prose such as
///   "Bearer authentication".
/// * `Basic <credentials>` where the credentials are base64 that decodes to
///   `user:password`.
///
/// [MaskMode.partial] falls back to the full mask.
class BearerTokenRule extends RedactionRule {
  /// Creates the rule.
  const BearerTokenRule({super.enabled, super.mode})
    : super(id: 'bearer_token');

  static final RegExp _header = RegExp(
    r'''(authorization["']?\s*[:=]\s*["']?)([^"'\r\n,}]+)''',
    caseSensitive: false,
  );
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
      final value = m[2]!.trimRight();
      if (value.isEmpty) continue;
      yield RedactionSpan(
        start: m.start,
        end: m.start + m[1]!.length + value.length,
        prefix: m[1]!,
        value: value,
      );
    }
    for (final m in _bearer.allMatches(input)) {
      final token = m[2]!;
      if (!_tokenMarker.hasMatch(token)) continue;
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
