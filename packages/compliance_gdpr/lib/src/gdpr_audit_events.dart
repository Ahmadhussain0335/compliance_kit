/// Audit event types recorded by compliance_gdpr.
///
/// Event metadata only contains purpose ids, policy versions, counts and
/// source ids defined by the app, never personal data.
abstract final class GdprAuditEvents {
  /// Audit source for every event from this package.
  static const String source = 'compliance_gdpr';

  /// The user granted consent for a purpose.
  static const String consentGranted = 'consent_granted';

  /// The user declined a purpose they had not granted before.
  static const String consentDenied = 'consent_denied';

  /// The user withdrew a previously granted consent.
  static const String consentWithdrawn = 'consent_withdrawn';

  /// Stored consent was given under an older policy version.
  static const String consentPolicyChanged = 'consent_policy_changed';

  /// A data export finished.
  static const String dataExported = 'data_exported';

  /// The user confirmed a deletion request.
  static const String dataDeletionRequested = 'data_deletion_requested';

  /// A deletion run finished (see metadata for failures).
  static const String dataDeletionCompleted = 'data_deletion_completed';
}
