import 'consent_policy.dart';
import 'consent_record.dart';

/// Whether the user needs to be asked for consent.
enum ConsentStatus {
  /// No decision has been stored for any optional purpose.
  notAsked,

  /// Decisions exist, but only for an older policy version.
  policyChanged,

  /// Some optional purposes have no decision under the current version, for
  /// example because a purpose was added without changing the version.
  incomplete,

  /// Every optional purpose has a decision under the current version.
  upToDate,
}

/// An immutable snapshot of the user's consent.
final class ConsentState {
  /// Builds the state for [policy] from the stored [history].
  factory ConsentState.fromHistory(
    ConsentPolicy policy,
    List<ConsentRecord> history,
  ) {
    // Only the latest record per purpose counts, whatever its version, so
    // a later denial is never revived by switching back to an older policy
    // version.
    final latest = <String, ConsentRecord>{};
    for (final record in history) {
      latest[record.purposeId] = record;
    }
    final current = <String, ConsentRecord>{};
    var hasOlder = false;
    String? previousVersion;
    for (final record in history) {
      if (record.policyVersion != policy.version) {
        hasOlder = true;
        previousVersion = record.policyVersion;
      }
    }
    for (final record in latest.values) {
      if (record.policyVersion == policy.version) {
        current[record.purposeId] = record;
      }
    }
    final optional = policy.optionalPurposes;
    final ConsentStatus status;
    if (optional.every((p) => current.containsKey(p.id))) {
      status = ConsentStatus.upToDate;
    } else if (current.isNotEmpty) {
      status = ConsentStatus.incomplete;
    } else if (hasOlder) {
      status = ConsentStatus.policyChanged;
    } else {
      status = ConsentStatus.notAsked;
    }
    return ConsentState._(
      policy,
      Map.unmodifiable(current),
      status,
      previousVersion,
    );
  }

  const ConsentState._(
    this.policy,
    this.decisions,
    this.status,
    this.previousPolicyVersion,
  );

  /// The policy this state was computed for.
  final ConsentPolicy policy;

  /// Latest decision per purpose under the current policy version.
  final Map<String, ConsentRecord> decisions;

  /// Whether the user needs to be asked.
  final ConsentStatus status;

  /// The most recent older policy version found in the history, if any.
  /// While this is set and [needsConsent] is `true`, the UI shows the
  /// policy-changed notice.
  final String? previousPolicyVersion;

  /// Whether the consent prompt should be shown.
  bool get needsConsent => status != ConsentStatus.upToDate;

  /// Whether the user should be told that the policy changed: consent is
  /// needed and decisions under an older version exist.
  bool get policyChangedNotice => needsConsent && previousPolicyVersion != null;

  /// Whether processing for [purposeId] is allowed.
  ///
  /// Required purposes are always allowed. Optional purposes are allowed
  /// only if consent was granted under the current policy version. Unknown
  /// purposes are never allowed.
  bool isGranted(String purposeId) {
    final purpose = policy.purpose(purposeId);
    if (purpose == null) return false;
    if (purpose.required) return true;
    return decisions[purposeId]?.granted ?? false;
  }

  /// Whether the user has decided on [purposeId] under the current version.
  bool hasDecided(String purposeId) => decisions.containsKey(purposeId);

  /// Ids of purposes that are currently allowed, including required ones.
  Set<String> get grantedPurposeIds => {
    for (final p in policy.purposes)
      if (isGranted(p.id)) p.id,
  };
}
