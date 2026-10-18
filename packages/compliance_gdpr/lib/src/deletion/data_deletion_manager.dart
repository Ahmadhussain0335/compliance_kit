import 'dart:async';

import 'package:compliance_core/compliance_core.dart';

import '../gdpr_audit_events.dart';
import 'data_eraser.dart';

/// Calls the app's backend to delete the account and server-side data.
///
/// Complete normally when the backend accepted the request; throw on
/// failure. The package does not know your API; authenticate the request
/// the same way as other calls.
typedef ServerDeletionCallback = Future<void> Function();

/// Result for one deletion step.
final class SourceDeletionResult {
  /// Creates a result.
  const SourceDeletionResult({
    required this.id,
    required this.status,
    this.reason,
    this.error,
    this.stackTrace,
  });

  /// The eraser id, or [DataDeletionManager.serverStepId] for the server.
  final String id;

  /// What happened.
  final ErasureStatus status;

  /// Machine-readable reason for [ErasureStatus.skipped] or
  /// [ErasureStatus.failed], for example `server_failed` or `timeout`.
  final String? reason;

  /// The error, if the step failed.
  final Object? error;

  /// Stack trace of [error].
  final StackTrace? stackTrace;
}

/// Result of a deletion run.
final class DeletionReport {
  /// Creates a report.
  DeletionReport({
    required this.cancelled,
    required this.server,
    required List<SourceDeletionResult> local,
    required DateTime finishedAt,
  }) : local = List.unmodifiable(local),
       finishedAt = finishedAt.toUtc();

  /// The user did not confirm; nothing was deleted.
  final bool cancelled;

  /// Result of the server step, or `null` if no server callback is set.
  final SourceDeletionResult? server;

  /// One result per registered eraser.
  final List<SourceDeletionResult> local;

  /// When the run finished, in UTC.
  final DateTime finishedAt;

  /// Every step, server first.
  List<SourceDeletionResult> get steps => [?server, ...local];

  /// Steps that failed or were skipped because of a failure, and should be
  /// retried with [DataDeletionManager.retry].
  List<SourceDeletionResult> get needsRetry => [
    for (final step in steps)
      if (step.status == ErasureStatus.failed ||
          step.reason == DataDeletionManager.reasonServerFailed)
        step,
  ];

  /// Whether every step succeeded (or was skipped for a benign reason).
  bool get isComplete => !cancelled && needsRetry.isEmpty;
}

/// Runs "delete my account" (GDPR Art. 17): server-side deletion through a
/// callback, then every registered local [DataEraser].
///
/// Flow of [deleteAll]:
/// 1. Ask for confirmation through `confirm`, if given. If it returns
///    `false`, nothing is deleted.
/// 2. Record `data_deletion_requested`.
/// 3. Call [serverDeletion], if set. If it fails and
///    [eraseLocalWhenServerFails] is `false` (the default), local data is
///    kept so the signed-in user can retry; local steps are reported as
///    skipped with reason [reasonServerFailed].
/// 4. Run every eraser. A failing eraser does not stop the others.
/// 5. Record `data_deletion_completed` with counts.
///
/// Calling [deleteAll] while a run is in progress returns the running
/// operation instead of starting a second one.
final class DataDeletionManager {
  /// Creates a manager.
  DataDeletionManager({
    this.serverDeletion,
    this.eraseLocalWhenServerFails = false,
    this.auditTrail,
    this.stepTimeout = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Step id used for the server deletion step.
  static const String serverStepId = 'server';

  /// Reason for local steps skipped because the server step failed.
  static const String reasonServerFailed = 'server_failed';

  /// Reason for a step that exceeded [stepTimeout].
  static const String reasonTimeout = 'timeout';

  /// Reason for a step that threw.
  static const String reasonError = 'error';

  /// Reason for a retry step that is no longer registered.
  static const String reasonNotRegistered = 'not_registered';

  static final RegExp _idPattern = RegExp(r'^[a-z][a-z0-9_.\-]*$');

  /// Backend deletion, or `null` for apps without server-side data.
  final ServerDeletionCallback? serverDeletion;

  /// Whether local data is erased even if the server step failed.
  final bool eraseLocalWhenServerFails;

  /// Optional audit trail.
  final AuditTrail? auditTrail;

  /// Maximum time per step.
  final Duration stepTimeout;

  final DateTime Function() _clock;
  final List<DataEraser> _erasers = [];
  Future<DeletionReport>? _running;

  /// Ids of registered erasers.
  List<String> get eraserIds => [for (final e in _erasers) e.id];

  /// Whether a deletion is in progress.
  bool get isRunning => _running != null;

  /// Registers [eraser].
  ///
  /// Throws [InvalidConfigurationException] for an invalid, reserved or
  /// duplicate id.
  void register(DataEraser eraser) {
    final id = eraser.id;
    if (!_idPattern.hasMatch(id) || id.length > 64 || id == serverStepId) {
      throw InvalidConfigurationException(
        'Eraser id "$id" must match [a-z][a-z0-9_.-]*, be at most 64 '
        'characters and not be "$serverStepId".',
      );
    }
    if (_erasers.any((e) => e.id == id)) {
      throw InvalidConfigurationException(
        'Eraser "$id" is already registered.',
      );
    }
    _erasers.add(eraser);
  }

  /// Removes the eraser with [id]. Returns whether it was registered.
  bool unregister(String id) {
    final before = _erasers.length;
    _erasers.removeWhere((e) => e.id == id);
    return _erasers.length != before;
  }

  /// Deletes the account and all registered local data. See the class
  /// documentation for the flow.
  Future<DeletionReport> deleteAll({Future<bool> Function()? confirm}) =>
      _guard(() async {
        if (confirm != null && !await confirm()) {
          return DeletionReport(
            cancelled: true,
            server: null,
            local: const [],
            finishedAt: _clock(),
          );
        }
        return _run(
          runServer: serverDeletion != null,
          erasers: List.of(_erasers),
          missing: const [],
        );
      });

  /// Runs again only the steps of [previous] that need a retry.
  ///
  /// No confirmation is asked, because the user already confirmed the
  /// original request.
  Future<DeletionReport> retry(DeletionReport previous) => _guard(() {
    final ids = {for (final s in previous.needsRetry) s.id};
    final erasers = [
      for (final e in _erasers)
        if (ids.contains(e.id)) e,
    ];
    final missing = [
      for (final id in ids)
        if (id != serverStepId && !_erasers.any((e) => e.id == id)) id,
    ];
    return _run(
      runServer: ids.contains(serverStepId) && serverDeletion != null,
      erasers: erasers,
      missing: missing,
    );
  });

  Future<DeletionReport> _guard(Future<DeletionReport> Function() body) {
    final running = _running;
    if (running != null) return running;
    final future = body().whenComplete(() => _running = null);
    _running = future;
    return future;
  }

  Future<DeletionReport> _run({
    required bool runServer,
    required List<DataEraser> erasers,
    required List<String> missing,
  }) async {
    await _audit(GdprAuditEvents.dataDeletionRequested, {
      'server': runServer,
      'local_steps': erasers.length,
    });

    SourceDeletionResult? server;
    if (runServer) {
      server = await _step(serverStepId, () async {
        await serverDeletion!();
        return ErasureStatus.deleted;
      });
    }
    final serverFailed = server?.status == ErasureStatus.failed;
    final local = <SourceDeletionResult>[];
    for (final eraser in erasers) {
      if (serverFailed && !eraseLocalWhenServerFails) {
        local.add(
          SourceDeletionResult(
            id: eraser.id,
            status: ErasureStatus.skipped,
            reason: reasonServerFailed,
          ),
        );
      } else {
        local.add(await _step(eraser.id, eraser.erase));
      }
    }
    for (final id in missing) {
      local.add(
        SourceDeletionResult(
          id: id,
          status: ErasureStatus.skipped,
          reason: reasonNotRegistered,
        ),
      );
    }
    final report = DeletionReport(
      cancelled: false,
      server: server,
      local: local,
      finishedAt: _clock(),
    );
    await _audit(GdprAuditEvents.dataDeletionCompleted, {
      'complete': report.isComplete,
      'deleted': report.steps
          .where((s) => s.status == ErasureStatus.deleted)
          .length,
      'skipped': report.steps
          .where((s) => s.status == ErasureStatus.skipped)
          .length,
      'failed': report.steps
          .where((s) => s.status == ErasureStatus.failed)
          .length,
    });
    return report;
  }

  Future<SourceDeletionResult> _step(
    String id,
    Future<ErasureStatus> Function() action,
  ) async {
    try {
      final status = await action().timeout(stepTimeout);
      if (status == ErasureStatus.failed) {
        return SourceDeletionResult(
          id: id,
          status: ErasureStatus.failed,
          reason: reasonError,
        );
      }
      return SourceDeletionResult(id: id, status: status);
    } on TimeoutException catch (e, st) {
      return SourceDeletionResult(
        id: id,
        status: ErasureStatus.failed,
        reason: reasonTimeout,
        error: e,
        stackTrace: st,
      );
    } on Object catch (e, st) {
      return SourceDeletionResult(
        id: id,
        status: ErasureStatus.failed,
        reason: reasonError,
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _audit(String type, Map<String, Object?> metadata) async {
    final trail = auditTrail;
    if (trail == null) return;
    try {
      await trail.record(
        AuditEvent(
          type: type,
          source: GdprAuditEvents.source,
          timestamp: _clock(),
          metadata: metadata,
        ),
      );
    } on Object {
      // A failing audit trail must not block deletion.
    }
  }
}
