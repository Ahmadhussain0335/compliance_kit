import 'dart:convert';
import 'dart:math';

import 'package:compliance_core/compliance_core.dart';
import 'package:crypto/crypto.dart';

import 'redaction_rule.dart';

/// Produces the replacement text for a sensitive value.
final class Masker {
  /// Creates a masker.
  ///
  /// [hashKey] is the HMAC key for [MaskMode.hash]. It must be at least
  /// [minHashKeyLength] bytes. If omitted, a random key is generated, so
  /// hashes are stable within one process but differ between runs.
  ///
  /// Throws [InvalidConfigurationException] if [hashKey] is too short.
  Masker({List<int>? hashKey}) : _hmac = Hmac(sha256, _resolveKey(hashKey));

  /// Minimum length of a hash key, in bytes.
  static const int minHashKeyLength = 16;

  /// Number of hex characters of the HMAC kept in hashed output.
  static const int hashLength = 12;

  final Hmac _hmac;

  /// Masks [value] found by [rule] according to the rule's mode.
  String mask(RedactionRule rule, String value) => switch (rule.mode) {
    MaskMode.full => rule.fullMask,
    MaskMode.partial => rule.partialMask(value),
    MaskMode.hash => '[HASH:${rule.id}:${hash(value)}]',
  };

  /// Returns the first [hashLength] hex characters of HMAC-SHA-256 of
  /// [value].
  String hash(String value) =>
      _hmac.convert(utf8.encode(value)).toString().substring(0, hashLength);

  static List<int> _resolveKey(List<int>? key) {
    if (key == null) {
      final random = Random.secure();
      return List<int>.generate(32, (_) => random.nextInt(256));
    }
    if (key.length < minHashKeyLength) {
      throw const InvalidConfigurationException(
        'hashKey must be at least $minHashKeyLength bytes.',
      );
    }
    return List<int>.of(key);
  }
}
