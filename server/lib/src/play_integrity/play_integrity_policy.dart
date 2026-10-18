import '../verification_result.dart';

/// Checks a decoded Play Integrity payload (`tokenPayloadExternal`) against
/// Google's recommended checks.
///
/// See https://developer.android.com/google/play/integrity/verdicts
final class PlayIntegrityPolicy {
  /// Creates a policy.
  ///
  /// [certificateSha256Digests] are the base64url SHA-256 digests of your
  /// app signing certificate(s) as shown in Play Console. If empty, the
  /// digest is not checked.
  const PlayIntegrityPolicy({
    required this.packageName,
    this.certificateSha256Digests = const {},
    this.maxTokenAge = const Duration(minutes: 2),
    this.requireLicensed = true,
    this.requiredDeviceVerdict = 'MEETS_DEVICE_INTEGRITY',
  });

  /// Expected application id.
  final String packageName;

  /// Accepted signing certificate digests.
  final Set<String> certificateSha256Digests;

  /// Maximum age of the token, measured from `timestampMillis`.
  final Duration maxTokenAge;

  /// Whether `appLicensingVerdict` must be `LICENSED`.
  final bool requireLicensed;

  /// Device label that must be present, for example
  /// `MEETS_DEVICE_INTEGRITY` or `MEETS_STRONG_INTEGRITY`.
  final String requiredDeviceVerdict;

  /// Checks [payload] for a standard request bound to [expectedRequestHash].
  VerificationResult check(
    Map<String, Object?> payload, {
    required String expectedRequestHash,
    DateTime? now,
  }) {
    final failures = <String>[];
    final request = _map(payload['requestDetails']);
    final app = _map(payload['appIntegrity']);
    final device = _map(payload['deviceIntegrity']);
    final account = _map(payload['accountDetails']);

    // 1. Request details first: package, request hash, freshness.
    if (request['requestPackageName'] != packageName) {
      failures.add('package_name');
    }
    if (request['requestHash'] != expectedRequestHash) {
      failures.add('request_hash');
    }
    final timestamp = int.tryParse('${request['timestampMillis']}');
    final current = (now ?? DateTime.now()).toUtc();
    if (timestamp == null) {
      failures.add('timestamp');
    } else {
      final issued = DateTime.fromMillisecondsSinceEpoch(
        timestamp,
        isUtc: true,
      );
      final age = current.difference(issued);
      if (age > maxTokenAge || age < const Duration(minutes: -1)) {
        failures.add('timestamp');
      }
    }

    // 2. App integrity.
    if (app['appRecognitionVerdict'] != 'PLAY_RECOGNIZED') {
      failures.add('app_recognition');
    } else {
      if (app['packageName'] != packageName) failures.add('app_package_name');
      if (certificateSha256Digests.isNotEmpty) {
        final digests = _list(app['certificateSha256Digest']);
        if (!digests.any(certificateSha256Digests.contains)) {
          failures.add('certificate');
        }
      }
    }

    // 3. Device integrity.
    final labels = _list(device['deviceRecognitionVerdict']);
    if (!labels.contains(requiredDeviceVerdict)) {
      failures.add('device_integrity');
    }

    // 4. Licensing.
    if (requireLicensed && account['appLicensingVerdict'] != 'LICENSED') {
      failures.add('licensing');
    }

    return failures.isEmpty
        ? const VerificationResult.pass()
        : VerificationResult.fail(failures);
  }

  static List<Object?> _list(Object? value) =>
      value is List ? value.cast<Object?>() : const [];

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : const {};
}
