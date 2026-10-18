import '../gdpr_exceptions.dart';

/// One consent decision, as stored.
///
/// Records are append-only: a change of mind adds a new record rather than
/// editing the old one, so the history can be shown as proof of consent.
final class ConsentRecord {
  /// Creates a record. [timestamp] is converted to UTC.
  ConsentRecord({
    required this.purposeId,
    required this.granted,
    required DateTime timestamp,
    required this.policyVersion,
  }) : timestamp = timestamp.toUtc();

  /// Decodes a record produced by [toJson].
  ///
  /// Throws [ConsentException] if [json] is malformed.
  factory ConsentRecord.fromJson(Map<String, Object?> json) {
    final purposeId = json['purpose_id'];
    final granted = json['granted'];
    final timestamp = json['timestamp'];
    final version = json['policy_version'];
    if (purposeId is! String ||
        granted is! bool ||
        timestamp is! String ||
        version is! String) {
      throw const ConsentException('Malformed consent record.');
    }
    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) {
      throw const ConsentException('Malformed consent record timestamp.');
    }
    return ConsentRecord(
      purposeId: purposeId,
      granted: granted,
      timestamp: parsed,
      policyVersion: version,
    );
  }

  /// The purpose the decision applies to.
  final String purposeId;

  /// `true` if consent was granted, `false` if denied or withdrawn.
  final bool granted;

  /// When the decision was made, in UTC.
  final DateTime timestamp;

  /// The policy version the user saw when deciding.
  final String policyVersion;

  /// Encodes this record as a JSON-compatible map.
  Map<String, Object?> toJson() => {
    'purpose_id': purposeId,
    'granted': granted,
    'timestamp': timestamp.toIso8601String(),
    'policy_version': policyVersion,
  };

  @override
  bool operator ==(Object other) =>
      other is ConsentRecord &&
      other.purposeId == purposeId &&
      other.granted == granted &&
      other.timestamp == timestamp &&
      other.policyVersion == policyVersion;

  @override
  int get hashCode => Object.hash(purposeId, granted, timestamp, policyVersion);
}
