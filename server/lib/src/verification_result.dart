/// Outcome of a verification: pass, or fail with machine-readable reasons.
final class VerificationResult {
  /// A passing result.
  const VerificationResult.pass() : failures = const [];

  /// A failing result with [failures], for example `['nonce']`.
  const VerificationResult.fail(this.failures);

  /// Reasons the check failed. Empty when it passed.
  final List<String> failures;

  /// Whether every check passed.
  bool get ok => failures.isEmpty;

  /// JSON body for the HTTP response. Contains reason codes only.
  Map<String, Object?> toJson() => {'ok': ok, if (!ok) 'failures': failures};
}
