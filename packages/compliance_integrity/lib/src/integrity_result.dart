/// The kind of token returned by a successful request.
enum IntegrityTokenKind {
  /// A Google Play Integrity token from a standard request (Android).
  playIntegrityStandard,

  /// An App Attest attestation object for a new key (iOS). Send it to your
  /// server once; the server verifies it and stores the key's public key.
  appAttestAttestation,

  /// An App Attest assertion signed with an attested key (iOS).
  appAttestAssertion,
}

/// Outcome of an integrity request.
///
/// Switch over the subtypes to handle every case:
///
/// ```dart
/// switch (await integrity.requestToken(hash)) {
///   case IntegritySuccess(:final token, :final kind):
///     await api.verify(token, kind);
///   case IntegrityUnsupported():
///   case IntegrityPlayServicesMissing():
///     // Fall back to other risk signals.
///   case IntegrityNetworkError() || IntegrityRateLimited():
///     // Retry later.
///   case IntegrityConfigurationError() || IntegrityPlatformError():
///     // Log and investigate.
/// }
/// ```
sealed class IntegrityResult {
  const IntegrityResult();

  /// Whether a token was obtained. This does not mean the device passed:
  /// only your server can decide that after verifying the token.
  bool get isSuccess => this is IntegritySuccess;

  /// Short, stable name of the result, used in audit events.
  String get resultType;
}

/// A token was obtained. Send [token] to your server for verification.
final class IntegritySuccess extends IntegrityResult {
  /// Creates a success result.
  const IntegritySuccess({required this.token, required this.kind, this.keyId});

  /// The token or attestation/assertion, base64-encoded. Treat it as a
  /// secret in transit and never log it.
  final String token;

  /// What [token] contains.
  final IntegrityTokenKind kind;

  /// The App Attest key id (iOS only), base64-encoded. The server needs it
  /// to find the stored public key.
  final String? keyId;

  @override
  String get resultType => 'success';

  @override
  String toString() => 'IntegritySuccess(kind: ${kind.name})';
}

/// The request did not produce a token.
sealed class IntegrityFailure extends IntegrityResult {
  const IntegrityFailure({this.message, this.platformCode});

  /// Developer-facing detail from the platform, if any. May be shown in
  /// logs; does not contain the token.
  final String? message;

  /// The platform's own error code, if any, for diagnostics.
  final String? platformCode;

  /// Whether retrying later may succeed.
  bool get isRetryable => false;

  @override
  String toString() =>
      '$resultType(platformCode: $platformCode, message: $message)';
}

/// The device or OS cannot produce integrity tokens, for example the iOS
/// simulator, an older device, or a platform other than Android and iOS.
final class IntegrityUnsupported extends IntegrityFailure {
  /// Creates the result.
  const IntegrityUnsupported({super.message, super.platformCode});

  @override
  String get resultType => 'unsupported';
}

/// Google Play services or the Play Store is missing, disabled or too old
/// (for example on Huawei devices without Google services).
final class IntegrityPlayServicesMissing extends IntegrityFailure {
  /// Creates the result.
  const IntegrityPlayServicesMissing({super.message, super.platformCode});

  @override
  String get resultType => 'play_services_missing';
}

/// A network problem, or the attestation service was temporarily
/// unavailable.
final class IntegrityNetworkError extends IntegrityFailure {
  /// Creates the result.
  const IntegrityNetworkError({super.message, super.platformCode});

  @override
  bool get isRetryable => true;

  @override
  String get resultType => 'network_error';
}

/// Too many requests. Retry with exponential backoff.
final class IntegrityRateLimited extends IntegrityFailure {
  /// Creates the result.
  const IntegrityRateLimited({super.message, super.platformCode});

  @override
  bool get isRetryable => true;

  @override
  String get resultType => 'rate_limited';
}

/// The app or plugin is misconfigured, for example a missing or invalid
/// Google Cloud project number, a missing App Attest entitlement, or an
/// invalid request hash.
final class IntegrityConfigurationError extends IntegrityFailure {
  /// Creates the result.
  const IntegrityConfigurationError({super.message, super.platformCode});

  @override
  String get resultType => 'configuration_error';
}

/// Any other platform failure.
final class IntegrityPlatformError extends IntegrityFailure {
  /// Creates the result.
  const IntegrityPlatformError({
    super.message,
    super.platformCode,
    this.retryable = false,
  });

  /// Whether the platform marked the error as transient.
  final bool retryable;

  @override
  bool get isRetryable => retryable;

  @override
  String get resultType => 'platform_error';
}
