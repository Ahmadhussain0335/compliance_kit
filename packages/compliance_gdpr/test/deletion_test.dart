import 'dart:async';

import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_gdpr/compliance_gdpr.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _FailingTrail implements AuditTrail {
  @override
  Stream<AuditEvent> get events => const Stream.empty();

  @override
  Future<void> record(AuditEvent event) => Future.error(StateError('down'));
}

/// A fake local store that can be wiped.
class _FakeStore {
  Map<String, String>? data = {'name': 'Test User'};
  int eraseCalls = 0;

  Future<ErasureStatus> erase() async {
    eraseCalls++;
    if (data == null) return ErasureStatus.skipped;
    data = null;
    return ErasureStatus.deleted;
  }
}

Future<bool> _yes() async => true;

void main() {
  late InMemoryAuditTrail trail;

  setUp(() => trail = InMemoryAuditTrail());

  DataDeletionManager manager({
    ServerDeletionCallback? server,
    bool eraseLocalWhenServerFails = false,
  }) => DataDeletionManager(
    serverDeletion: server,
    eraseLocalWhenServerFails: eraseLocalWhenServerFails,
    auditTrail: trail,
    clock: steppingClock(),
    stepTimeout: const Duration(milliseconds: 100),
  );

  test('deletes server data first, then every local source', () async {
    final calls = <String>[];
    final db = _FakeStore();
    final deletion =
        manager(
            server: () async {
              calls.add('server');
              return ErasureStatus.deleted;
            },
          )
          ..register(
            CallbackDataEraser('db', () {
              calls.add('db');
              return db.erase();
            }),
          )
          ..register(
            CallbackDataEraser('cache', () async {
              calls.add('cache');
              return ErasureStatus.skipped;
            }),
          );

    final report = await deletion.deleteAll(confirm: () async => true);
    expect(calls, ['server', 'db', 'cache']);
    expect(report.cancelled, isFalse);
    expect(report.isComplete, isTrue);
    expect(report.server!.status, ErasureStatus.deleted);
    expect(report.local.map((r) => r.status), [
      ErasureStatus.deleted,
      ErasureStatus.skipped,
    ]);
    expect(report.steps.map((s) => s.id), ['server', 'db', 'cache']);
    expect(report.finishedAt.isUtc, isTrue);
    expect(db.data, isNull);

    await Future<void>.delayed(Duration.zero);
    expect(trail.history.map((e) => e.type), [
      'data_deletion_requested',
      'data_deletion_completed',
    ]);
    expect(trail.history.last.metadata, {
      'complete': true,
      'deleted': 2,
      'skipped': 1,
      'failed': 0,
    });
  });

  test('cancelled confirmation deletes nothing', () async {
    final db = _FakeStore();
    final deletion = manager()..register(CallbackDataEraser('db', db.erase));
    final report = await deletion.deleteAll(confirm: () async => false);
    expect(report.cancelled, isTrue);
    expect(report.isComplete, isFalse);
    expect(db.eraseCalls, 0);
    expect(trail.history, isEmpty);
  });

  test('server failure keeps local data by default', () async {
    final db = _FakeStore();
    final deletion = manager(server: () async => throw StateError('503'))
      ..register(CallbackDataEraser('db', db.erase));
    final report = await deletion.deleteAll(confirm: _yes);
    expect(report.server!.status, ErasureStatus.failed);
    expect(report.server!.reason, DataDeletionManager.reasonError);
    expect(report.server!.error, isA<StateError>());
    expect(report.local.single.status, ErasureStatus.skipped);
    expect(report.local.single.reason, DataDeletionManager.reasonServerFailed);
    expect(report.isComplete, isFalse);
    expect(report.needsRetry.map((s) => s.id), ['server', 'db']);
    expect(db.data, isNotNull);
  });

  test('server failure can still erase local data when configured', () async {
    final db = _FakeStore();
    final deletion = manager(
      server: () async => throw StateError('503'),
      eraseLocalWhenServerFails: true,
    )..register(CallbackDataEraser('db', db.erase));
    final report = await deletion.deleteAll(confirm: _yes);
    expect(report.local.single.status, ErasureStatus.deleted);
    expect(report.needsRetry.map((s) => s.id), ['server']);
  });

  test(
    'a failing eraser does not stop the others; retry runs only failures',
    () async {
      var attempts = 0;
      final db = _FakeStore();
      final deletion = manager()
        ..register(
          CallbackDataEraser('flaky', () async {
            attempts++;
            if (attempts == 1) throw StateError('locked');
            return ErasureStatus.deleted;
          }),
        )
        ..register(CallbackDataEraser('db', db.erase))
        ..register(
          CallbackDataEraser(
            'slow',
            () => Future.delayed(
              const Duration(seconds: 5),
              () => ErasureStatus.deleted,
            ),
          ),
        )
        ..register(
          CallbackDataEraser(
            'reports_failed',
            () async => ErasureStatus.failed,
          ),
        );

      final first = await deletion.deleteAll(confirm: _yes);
      expect(first.local.map((r) => r.status), [
        ErasureStatus.failed,
        ErasureStatus.deleted,
        ErasureStatus.failed,
        ErasureStatus.failed,
      ]);
      expect(first.local[2].reason, DataDeletionManager.reasonTimeout);
      expect(first.local[3].reason, DataDeletionManager.reasonError);

      deletion.unregister('slow');
      final second = await deletion.retry(first);
      expect(second.local.map((r) => '${r.id}:${r.status.name}'), [
        'flaky:deleted',
        'reports_failed:failed',
        'slow:skipped',
      ]);
      expect(second.local.last.reason, DataDeletionManager.reasonNotRegistered);
      expect(db.eraseCalls, 1);
    },
  );

  test('retry re-runs the server step', () async {
    var serverCalls = 0;
    final deletion = manager(
      server: () async {
        serverCalls++;
        if (serverCalls == 1) throw StateError('offline');
        return ErasureStatus.deleted;
      },
    )..register(CallbackDataEraser('db', _FakeStore().erase));
    final first = await deletion.deleteAll(confirm: _yes);
    final second = await deletion.retry(first);
    expect(serverCalls, 2);
    expect(second.isComplete, isTrue);
  });

  test('running twice is safe and idempotent', () async {
    final db = _FakeStore();
    final deletion = manager()..register(CallbackDataEraser('db', db.erase));
    final first = await deletion.deleteAll(confirm: _yes);
    final second = await deletion.deleteAll(confirm: _yes);
    expect(first.local.single.status, ErasureStatus.deleted);
    expect(second.local.single.status, ErasureStatus.skipped);
    expect(second.isComplete, isTrue);
  });

  test('concurrent calls share one run', () async {
    final gate = Completer<void>();
    var runs = 0;
    final deletion = manager()
      ..register(
        CallbackDataEraser('db', () async {
          runs++;
          await gate.future;
          return ErasureStatus.deleted;
        }),
      );
    final a = deletion.deleteAll(confirm: _yes);
    final b = deletion.deleteAll(confirm: _yes);
    expect(deletion.isRunning, isTrue);
    expect(identical(a, b), isTrue);
    gate.complete();
    await a;
    expect(runs, 1);
    expect(deletion.isRunning, isFalse);
  });

  test('registration validates ids', () {
    Matcher invalid() => throwsA(isA<InvalidConfigurationException>());
    final deletion = manager();
    Future<ErasureStatus> noop() async => ErasureStatus.skipped;
    expect(() => deletion.register(CallbackDataEraser('Bad', noop)), invalid());
    expect(
      () => deletion.register(CallbackDataEraser('server', noop)),
      invalid(),
    );
    deletion.register(CallbackDataEraser('db', noop));
    expect(() => deletion.register(CallbackDataEraser('db', noop)), invalid());
    expect(deletion.eraserIds, ['db']);
    expect(deletion.unregister('db'), isTrue);
    expect(deletion.unregister('db'), isFalse);
  });

  test('a failing audit trail does not block deletion', () async {
    final report = await DataDeletionManager(
      auditTrail: _FailingTrail(),
    ).deleteAll(confirm: _yes);
    expect(report.isComplete, isTrue);
    expect(report.server, isNull);
  });
}
