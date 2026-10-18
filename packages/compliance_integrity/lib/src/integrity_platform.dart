import 'integrity_result.dart';

/// A token returned by the native side.
final class PlatformToken {
  /// Creates a platform token.
  const PlatformToken({required this.token, required this.kind, this.keyId});

  /// The token, base64-encoded.
  final String token;

  /// What the token contains.
  final IntegrityTokenKind kind;

  /// The App Attest key id (iOS only).
  final String? keyId;
}

/// A failure reported by the native side.
///
/// [code] is one of the `IntegrityErrorCodes` constants.
final class IntegrityPlatformException implements Exception {
  /// Creates the exception.
  const IntegrityPlatformException(
    this.code, {
    this.message,
    this.platformCode,
  });

  /// One of the `IntegrityErrorCodes` constants.
  final String code;

  /// Developer-facing detail.
  final String? message;

  /// The platform's own error code, for example `-6` or
  /// `DCError.featureUnsupported`.
  final String? platformCode;

  @override
  String toString() => 'IntegrityPlatformException($code, $platformCode)';
}

/// Error codes shared by the Dart and native layers.
abstract final class IntegrityErrorCodes {
  /// The device or OS cannot produce tokens.
  static const String unsupported = 'unsupported';

  /// Play services or the Play Store is missing or outdated.
  static const String playServicesMissing = 'play_services_missing';

  /// Network failure or temporarily unavailable service.
  static const String network = 'network';

  /// Too many requests.
  static const String rateLimited = 'rate_limited';

  /// Misconfiguration (project number, entitlement, request hash).
  static const String configuration = 'configuration';

  /// A transient platform failure that may succeed on retry.
  static const String transient = 'transient';

  /// Any other failure.
  static const String platform = 'platform';
}

/// The native integrity API, abstracted so it can be replaced in tests.
abstract interface class IntegrityPlatform {
  /// Whether the device can produce tokens.
  Future<bool> isSupported();

  /// Warms up the platform. On Android this prepares a standard integrity
  /// token provider for [cloudProjectNumber]. On iOS it creates an App
  /// Attest key if none exists.
  ///
  /// Throws [IntegrityPlatformException] on failure.
  Future<void> prepare({int? cloudProjectNumber});

  /// Requests a token bound to [requestHash].
  ///
  /// Throws [IntegrityPlatformException] on failure.
  Future<PlatformToken> requestToken({
    required String requestHash,
    int? cloudProjectNumber,
  });

  /// Discards the stored App Attest key (iOS) or token provider (Android),
  /// so the next request starts over.
  Future<void> reset();
}
