import 'dart:async';

import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_gdpr/compliance_gdpr.dart';
import 'package:compliance_logger/compliance_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// A trail whose record() never completes.
class _HangingTrail implements AuditTrail {
  @override
  Stream<AuditEvent> get events => const Stream.empty();

  @override
  Future<void> record(AuditEvent event) => Completer<void>().future;
}

class _FailingTrail implements AuditTrail {
  @override
  Stream<AuditEvent> get events => const Stream.empty();

  @override
  Future<void> record(AuditEvent event) => Future.error(StateError('down'));
}

class _FailingStore implements ConsentStore {
  @override
  Future<void> append(List<ConsentRecord> records) =>
      Future.error(StateError('disk full'));

  @override
  Future<void> clear() async {}

  @override
  Future<List<ConsentRecord>> load() async => const [];
}

Future<bool> _yes() async => true;

ConsentRecord _record(String id, bool granted, String version, int second) =>
    ConsentRecord(
      purposeId: id,
      granted: granted,
      timestamp: DateTime.utc(2026, 1, 1, 0, 0, second),
      policyVersion: version,
    );

void main() {
  group('consent', () {
    test('a hanging audit trail does not block consent changes', () async {
      final manager = ConsentManager(
        policy: testPolicy(),
        auditTrail: _HangingTrail(),
      );
      await manager.initialize();
      await manager.grant('analytics').timeout(const Duration(seconds: 1));
      await manager.withdraw('analytics').timeout(const Duration(seconds: 1));
      expect(manager.isGranted('analytics'), isFalse);
    });

    test('audit failures are reported to onAuditError', () async {
      final errors = <Object>[];
      final manager = ConsentManager(
        policy: testPolicy(),
        auditTrail: _FailingTrail(),
        onAuditError: errors.add,
      );
      await manager.initialize();
      await manager.grant('analytics');
      await Future<void>.delayed(Duration.zero);
      expect(errors.single, isA<StateError>());
    });

    test('reset clears records and notifies watchers', () async {
      final manager = ConsentManager(policy: testPolicy());
      await manager.initialize();
      await manager.acceptAll();
      final watched = <bool>[];
      final sub = manager.watch('analytics').listen(watched.add);
      await Future<void>.delayed(Duration.zero);
      await manager.reset();
      await Future<void>.delayed(Duration.zero);
      expect(manager.isGranted('analytics'), isFalse);
      expect(manager.state.status, ConsentStatus.notAsked);
      expect(await manager.history(), isEmpty);
      expect(watched, [true, false]);
      await sub.cancel();
    });

    test(
      'watch before initialize emits an error instead of crashing',
      () async {
        final manager = ConsentManager(policy: testPolicy());
        await expectLater(
          manager.watch('analytics'),
          emitsError(isA<ComplianceStateException>()),
        );
      },
    );

    test('a later denial is not revived by an older policy version', () async {
      final store = InMemoryConsentStore([
        _record('analytics', true, '1', 1),
        _record('analytics', false, '2', 2),
      ]);
      final manager = ConsentManager(
        policy: testPolicy(version: '1'),
        store: store,
      );
      await manager.initialize();
      expect(manager.isGranted('analytics'), isFalse);
      expect(manager.state.needsConsent, isTrue);
    });

    test('policy notice stays until every purpose is decided again', () async {
      final manager = ConsentManager(
        policy: testPolicy(version: '2'),
        store: InMemoryConsentStore([
          _record('analytics', true, '1', 1),
          _record('marketing', true, '1', 1),
        ]),
      );
      await manager.initialize();
      expect(manager.state.policyChangedNotice, isTrue);
      await manager.grant('analytics');
      expect(manager.state.status, ConsentStatus.incomplete);
      expect(manager.state.policyChangedNotice, isTrue);
      await manager.withdraw('marketing');
      expect(manager.state.policyChangedNotice, isFalse);
    });

    test('dispose waits for pending writes before closing', () async {
      final manager = ConsentManager(policy: testPolicy());
      await manager.initialize();
      final states = <ConsentState>[];
      manager.changes.listen(states.add);
      unawaited(manager.withdraw('analytics'));
      await manager.dispose();
      expect(states, hasLength(1));
    });

    test('fromJson validates stored values', () {
      expect(
        () => ConsentRecord.fromJson({
          'purpose_id': 'Bad Id',
          'granted': true,
          'timestamp': '2026-01-01T00:00:00Z',
          'policy_version': '1',
        }),
        throwsA(isA<ConsentException>()),
      );
      expect(
        () => ConsentRecord.fromJson({
          'purpose_id': 'a',
          'granted': true,
          'timestamp': '2026-01-01T00:00:00Z',
          'policy_version': 'v' * 65,
        }),
        throwsA(isA<ConsentException>()),
      );
    });
  });

  group('deletion', () {
    test(
      'a second run after the server account is gone wipes local data',
      () async {
        var serverCalls = 0;
        var dbAttempts = 0;
        var wiped = false;
        final deletion =
            DataDeletionManager(
              serverDeletion: () async {
                serverCalls++;
                return serverCalls == 1
                    ? ErasureStatus.deleted
                    : ErasureStatus.skipped;
              },
            )..register(
              CallbackDataEraser('db', () async {
                dbAttempts++;
                if (dbAttempts == 1) throw StateError('locked');
                wiped = true;
                return ErasureStatus.deleted;
              }),
            );
        final first = await deletion.deleteAll(confirm: _yes);
        expect(first.isComplete, isFalse);
        final second = await deletion.deleteAll(confirm: _yes);
        expect(second.server!.status, ErasureStatus.skipped);
        expect(second.isComplete, isTrue);
        expect(wiped, isTrue);
      },
    );

    test('retry of a cancelled or complete report runs nothing', () async {
      final trail = InMemoryAuditTrail();
      var erased = 0;
      final deletion = DataDeletionManager(auditTrail: trail)
        ..register(
          CallbackDataEraser('db', () async {
            erased++;
            return ErasureStatus.deleted;
          }),
        );
      final cancelled = await deletion.deleteAll(confirm: () async => false);
      expect(identical(await deletion.retry(cancelled), cancelled), isTrue);
      final done = await deletion.deleteAll(confirm: _yes);
      expect(identical(await deletion.retry(done), done), isTrue);
      expect(erased, 1);
      await Future<void>.delayed(Duration.zero);
      expect(trail.history, hasLength(2));
    });

    test('a hanging audit trail does not block deletion', () async {
      final report = await DataDeletionManager(
        auditTrail: _HangingTrail(),
      ).deleteAll(confirm: _yes).timeout(const Duration(seconds: 1));
      expect(report.isComplete, isTrue);
    });

    test('audit failures are reported', () async {
      final errors = <Object>[];
      await DataDeletionManager(
        auditTrail: _FailingTrail(),
        onAuditError: errors.add,
      ).deleteAll(confirm: _yes);
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(2));
    });
  });

  group('export', () {
    test('truncated redaction is reported as a failure', () async {
      final exporter = DataExporter(appId: 'a')
        ..register(
          RedactingDataSource(
            CallbackDataSource(
              'log',
              () async => List.generate(1500, (i) => 'line $i'),
            ),
            Redactor(),
          ),
        );
      final export = await exporter.export();
      expect(export.isComplete, isFalse);
      expect(export.results.single.status, SourceExportStatus.failed);
      expect(export.results.single.error, isA<IncompleteRedactionException>());
      expect(
        (export.results.single.error! as ComplianceException).code,
        'incomplete_redaction',
      );
    });

    test('a larger redactor limit exports the whole source', () async {
      final exporter = DataExporter(appId: 'a')
        ..register(
          RedactingDataSource(
            CallbackDataSource(
              'log',
              () async => List.generate(1500, (i) => 'line $i'),
            ),
            Redactor(maxCollectionLength: 5000),
          ),
        );
      final export = await exporter.export();
      expect(export.isComplete, isTrue);
      expect(export.results.single.data, hasLength(1500));
    });

    test('a throwing progress callback does not abort the export', () async {
      final exporter = DataExporter(appId: 'a')
        ..register(CallbackDataSource('x', () async => 1));
      final export = await exporter.export(
        onProgress: (_) => throw StateError('ui gone'),
      );
      expect(export.isComplete, isTrue);
    });

    test('hanging and failing audit trails', () async {
      final errors = <Object>[];
      await DataExporter(
        appId: 'a',
        auditTrail: _HangingTrail(),
      ).export().timeout(const Duration(seconds: 1));
      await DataExporter(
        appId: 'a',
        auditTrail: _FailingTrail(),
        onAuditError: errors.add,
      ).export();
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
    });
  });

  group('ui', () {
    Future<ConsentManager> manager(ConsentStore store) async {
      final m = ConsentManager(policy: testPolicy(), store: store);
      await m.initialize();
      return m;
    }

    testWidgets('a failed save shows an error and keeps the prompt open', (
      tester,
    ) async {
      final m = await manager(_FailingStore());
      Object? reported;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsentPrompt(manager: m, onError: (e, _) => reported = e),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('consent_accept_all')));
      await tester.pumpAndSettle();
      expect(find.text(const ConsentStrings().saveFailed), findsOneWidget);
      expect(reported, isA<StateError>());
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed toggle shows a snack bar', (tester) async {
      final m = await manager(_FailingStore());
      Object? reported;
      await tester.pumpWidget(
        MaterialApp(
          home: PrivacySettingsScreen(
            manager: m,
            onError: (e, _) => reported = e,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('consent_switch_analytics')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(reported, isA<StateError>());
    });

    testWidgets('system back does not close the consent dialog', (
      tester,
    ) async {
      final m = await manager(InMemoryConsentStore());
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showConsentDialog(context, manager: m),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('buttons have equal height when one label wraps', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsentChoiceButtons(
              acceptLabel: 'Alle akzeptieren',
              rejectLabel:
                  'Alle optionalen Zwecke ablehnen und nur notwendige nutzen',
              onAccept: () {},
              onReject: () {},
            ),
          ),
        ),
      );
      final accept = tester.getSize(
        find.byKey(const ValueKey('consent_accept_all')),
      );
      final reject = tester.getSize(
        find.byKey(const ValueKey('consent_reject_all')),
      );
      expect(accept, reject);
    });
  });
}
