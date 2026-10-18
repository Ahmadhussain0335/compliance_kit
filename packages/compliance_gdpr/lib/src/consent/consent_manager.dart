import 'dart:async';

import 'package:compliance_core/compliance_core.dart';

import '../gdpr_audit_events.dart';
import '../gdpr_exceptions.dart';
import 'consent_policy.dart';
import 'consent_record.dart';
import 'consent_state.dart';
import 'consent_store.dart';

/// Manages the user's consent for the purposes in a [ConsentPolicy].
///
/// ```dart
/// final consent = ConsentManager(policy: policy, store: myStore);
/// await consent.initialize();
/// if (consent.state.needsConsent) { /* show the consent prompt */ }
/// consent.watch('analytics').listen(analytics.setEnabled);
/// ```
///
/// Nothing optional is enabled until the user grants it. Withdrawing is a
/// single call to [withdraw]. Every change is appended to the [store] and,
/// if an [auditTrail] is given, recorded as an audit event with the purpose
/// id and policy version only.
final class ConsentManager {
  /// Creates a manager. Call [initialize] before using it.
  ConsentManager({
    required this.policy,
    ConsentStore? store,
    this.auditTrail,
    this.onAuditError,
    DateTime Function()? clock,
  }) : store = store ?? InMemoryConsentStore(),
       _clock = clock ?? DateTime.now;

  /// The current policy.
  final ConsentPolicy policy;

  /// Where consent records are stored.
  final ConsentStore store;

  /// Optional audit trail. Events are recorded in the background, so a
  /// slow or failing trail never delays or blocks a consent change.
  final AuditTrail? auditTrail;

  /// Called when recording an audit event fails, so the app can notice lost
  /// audit evidence. Receives the error only, never the event data.
  final void Function(Object error)? onAuditError;

  final DateTime Function() _clock;
  final StreamController<ConsentState> _changes =
      StreamController<ConsentState>.broadcast();
  ConsentState? _state;
  Future<void> _pending = Future<void>.value();

  /// Whether [initialize] has completed.
  bool get isInitialized => _state != null;

  /// The current consent state.
  ///
  /// Throws [ComplianceStateException] before [initialize] completes.
  ConsentState get state {
    final s = _state;
    if (s == null) {
      throw const ComplianceStateException(
        'ConsentManager.initialize() must complete before reading state.',
      );
    }
    return s;
  }

  /// Emits the new state after every change.
  Stream<ConsentState> get changes => _changes.stream;

  /// Emits whether [purposeId] is granted: the current value first, then
  /// every change. Use it to start or stop processing immediately, for
  /// example to disable analytics when consent is withdrawn.
  ///
  /// Throws [ConsentException] for an unknown purpose. If the stream is
  /// listened to before [initialize] completes, it emits a
  /// [ComplianceStateException] error and closes.
  Stream<bool> watch(String purposeId) {
    _purposeOrThrow(purposeId);
    StreamSubscription<ConsentState>? subscription;
    late final StreamController<bool> controller;
    controller = StreamController<bool>(
      onListen: () {
        if (_state == null) {
          controller.addError(
            const ComplianceStateException(
              'ConsentManager.initialize() must complete before watch().',
            ),
          );
          unawaited(controller.close());
          return;
        }
        var last = state.isGranted(purposeId);
        controller.add(last);
        subscription = changes.listen((next) {
          final granted = next.isGranted(purposeId);
          if (granted != last) {
            last = granted;
            controller.add(granted);
          }
        }, onDone: controller.close);
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  /// Loads stored records and computes the state.
  ///
  /// If stored decisions belong to an older policy version, a
  /// `consent_policy_changed` audit event is recorded and
  /// [ConsentState.status] is [ConsentStatus.policyChanged].
  Future<void> initialize() => _serialized(() async {
    final history = await store.load();
    final next = ConsentState.fromHistory(policy, history);
    _state = next;
    if (next.status == ConsentStatus.policyChanged) {
      _audit(GdprAuditEvents.consentPolicyChanged, {
        'previous_version': next.previousPolicyVersion,
        'policy_version': policy.version,
      });
    }
    _emit(next);
  });

  /// Whether processing for [purposeId] is allowed. See
  /// [ConsentState.isGranted].
  bool isGranted(String purposeId) => state.isGranted(purposeId);

  /// Grants consent for [purposeId]. No-op for required purposes.
  ///
  /// Throws [ConsentException] for an unknown purpose.
  Future<void> grant(String purposeId) => update({purposeId: true});

  /// Withdraws (or denies) consent for [purposeId].
  ///
  /// Throws [ConsentException] for an unknown or required purpose.
  Future<void> withdraw(String purposeId) => update({purposeId: false});

  /// Grants every optional purpose.
  Future<void> acceptAll() =>
      update({for (final p in policy.optionalPurposes) p.id: true});

  /// Denies every optional purpose.
  Future<void> rejectAll() =>
      update({for (final p in policy.optionalPurposes) p.id: false});

  /// Applies several decisions at once, for example from a settings screen.
  ///
  /// Decisions that match the current state under the current policy
  /// version are not stored again. Granting a required purpose is ignored.
  ///
  /// Throws [ConsentException] for an unknown purpose or for denying a
  /// required purpose; in that case nothing is stored.
  Future<void> update(Map<String, bool> decisions) => _serialized(() async {
    final current = state;
    for (final entry in decisions.entries) {
      final purpose = _purposeOrThrow(entry.key);
      if (purpose.required && !entry.value) {
        throw ConsentException(
          'Purpose "${purpose.id}" is strictly necessary and cannot be '
          'withdrawn.',
        );
      }
    }
    final now = _clock();
    final records = <ConsentRecord>[];
    final events = <(String, String)>[];
    for (final entry in decisions.entries) {
      final purpose = policy.purpose(entry.key)!;
      if (purpose.required) continue;
      final existing = current.decisions[purpose.id];
      if (existing != null && existing.granted == entry.value) continue;
      records.add(
        ConsentRecord(
          purposeId: purpose.id,
          granted: entry.value,
          timestamp: now,
          policyVersion: policy.version,
        ),
      );
      final type = entry.value
          ? GdprAuditEvents.consentGranted
          : current.isGranted(purpose.id)
          ? GdprAuditEvents.consentWithdrawn
          : GdprAuditEvents.consentDenied;
      events.add((type, purpose.id));
    }
    if (records.isEmpty) return;
    await store.append(records);
    final next = ConsentState.fromHistory(policy, await store.load());
    _state = next;
    _emit(next);
    for (final (type, purposeId) in events) {
      _audit(type, {'purpose': purposeId, 'policy_version': policy.version});
    }
  });

  /// Returns the full stored history, oldest first. Use it to show the user
  /// or an auditor when consent was given or withdrawn.
  Future<List<ConsentRecord>> history() => _serialized(store.load);

  /// Deletes every stored consent record and resets the state to
  /// [ConsentStatus.notAsked], notifying [changes] and [watch] listeners.
  ///
  /// Use this from a `DataEraser` when deleting an account, instead of
  /// clearing the store directly. Whether consent records must be kept as
  /// proof of consent after an erasure request is a legal decision for your
  /// organisation.
  Future<void> reset() => _serialized(() async {
    await store.clear();
    final next = ConsentState.fromHistory(policy, const []);
    _state = next;
    _emit(next);
  });

  /// Waits for pending changes, then closes the [changes] stream.
  Future<void> dispose() async {
    await _pending;
    await _changes.close();
  }

  ConsentPurpose _purposeOrThrow(String purposeId) {
    final purpose = policy.purpose(purposeId);
    if (purpose == null) {
      throw ConsentException('Unknown purpose "$purposeId".');
    }
    return purpose;
  }

  void _emit(ConsentState state) {
    if (!_changes.isClosed) _changes.add(state);
  }

  /// Records an audit event without waiting for the trail.
  void _audit(String type, Map<String, Object?> metadata) {
    final trail = auditTrail;
    if (trail == null) return;
    try {
      trail
          .record(
            AuditEvent(
              type: type,
              source: GdprAuditEvents.source,
              timestamp: _clock(),
              metadata: metadata,
            ),
          )
          .then<void>((_) {}, onError: _reportAuditError)
          .ignore();
    } on Object catch (e) {
      _reportAuditError(e);
    }
  }

  void _reportAuditError(Object error) {
    try {
      onAuditError?.call(error);
    } on Object {
      // The error handler must not break consent handling.
    }
  }

  /// Runs [action] after every previously queued action, so concurrent
  /// calls cannot interleave their reads and writes.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
