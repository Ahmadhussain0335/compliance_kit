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

void main() {
  group('ConsentPurpose and ConsentPolicy', () {
    test('validate ids, versions and duplicates', () {
      Matcher invalid() => throwsA(isA<InvalidConfigurationException>());
      expect(
        () => ConsentPurpose(id: 'Bad', title: 't', description: 'd'),
        invalid(),
      );
      expect(
        () => ConsentPurpose(id: 'a' * 49, title: 't', description: 'd'),
        invalid(),
      );
      final p = ConsentPurpose(id: 'a', title: 't', description: 'd');
      expect(() => ConsentPolicy(version: '', purposes: [p]), invalid());
      expect(() => ConsentPolicy(version: 'v' * 65, purposes: [p]), invalid());
      expect(() => ConsentPolicy(version: '1', purposes: [p, p]), invalid());
    });

    test('lookups', () {
      final policy = testPolicy();
      expect(policy.purpose('analytics')!.title, 'Analytics');
      expect(policy.purpose('nope'), isNull);
      expect(policy.optionalPurposes.map((p) => p.id), [
        'analytics',
        'marketing',
      ]);
    });
  });

  group('ConsentRecord', () {
    test('JSON round trip and equality', () {
      final record = ConsentRecord(
        purposeId: 'analytics',
        granted: true,
        timestamp: DateTime(2026, 1, 1, 10),
        policyVersion: '1',
      );
      expect(record.timestamp.isUtc, isTrue);
      final decoded = ConsentRecord.fromJson(record.toJson());
      expect(decoded, record);
      expect(decoded.hashCode, record.hashCode);
    });

    test('rejects malformed JSON', () {
      expect(
        () => ConsentRecord.fromJson(const {'purpose_id': 'a'}),
        throwsA(isA<ConsentException>()),
      );
      expect(
        () => ConsentRecord.fromJson(const {
          'purpose_id': 'a',
          'granted': true,
          'timestamp': 'nope',
          'policy_version': '1',
        }),
        throwsA(isA<ConsentException>()),
      );
      expect(const ConsentException('x').code, 'invalid_consent_operation');
    });
  });

  group('ConsentManager', () {
    late InMemoryAuditTrail trail;
    late InMemoryConsentStore store;
    late ConsentManager manager;

    setUp(() async {
      trail = InMemoryAuditTrail();
      store = InMemoryConsentStore();
      manager = ConsentManager(
        policy: testPolicy(),
        store: store,
        auditTrail: trail,
        clock: steppingClock(),
      );
      await manager.initialize();
    });

    tearDown(() => manager.dispose());

    test('state before initialize throws', () {
      final fresh = ConsentManager(policy: testPolicy());
      expect(fresh.isInitialized, isFalse);
      expect(() => fresh.state, throwsA(isA<ComplianceStateException>()));
    });

    test('nothing optional is granted by default', () {
      expect(manager.isInitialized, isTrue);
      expect(manager.state.status, ConsentStatus.notAsked);
      expect(manager.state.needsConsent, isTrue);
      expect(manager.isGranted('essential'), isTrue);
      expect(manager.isGranted('analytics'), isFalse);
      expect(manager.isGranted('marketing'), isFalse);
      expect(manager.isGranted('unknown'), isFalse);
      expect(manager.state.grantedPurposeIds, {'essential'});
    });

    test('grant, withdraw and audit events', () async {
      await manager.grant('analytics');
      expect(manager.isGranted('analytics'), isTrue);
      expect(manager.state.status, ConsentStatus.incomplete);

      await manager.withdraw('analytics');
      expect(manager.isGranted('analytics'), isFalse);

      await manager.withdraw('marketing');
      expect(manager.state.status, ConsentStatus.upToDate);
      expect(manager.state.needsConsent, isFalse);

      await Future<void>.delayed(Duration.zero);
      expect(trail.history.map((e) => e.type), [
        'consent_granted',
        'consent_withdrawn',
        'consent_denied',
      ]);
      expect(trail.history.first.metadata, {
        'purpose': 'analytics',
        'policy_version': '1',
      });
      expect(trail.history.first.source, 'compliance_gdpr');
    });

    test('history is append-only and records UTC timestamps', () async {
      await manager.grant('analytics');
      await manager.withdraw('analytics');
      final history = await manager.history();
      expect(history.map((r) => r.granted), [true, false]);
      expect(history.every((r) => r.timestamp.isUtc), isTrue);
      expect(history.every((r) => r.policyVersion == '1'), isTrue);
    });

    test('unchanged decisions are not stored again', () async {
      await manager.grant('analytics');
      await manager.grant('analytics');
      expect(await manager.history(), hasLength(1));
    });

    test('acceptAll and rejectAll cover every optional purpose', () async {
      await manager.acceptAll();
      expect(manager.state.grantedPurposeIds, {
        'essential',
        'analytics',
        'marketing',
      });
      expect(manager.state.status, ConsentStatus.upToDate);
      await manager.rejectAll();
      expect(manager.state.grantedPurposeIds, {'essential'});
    });

    test(
      'required purposes cannot be withdrawn; granting is a no-op',
      () async {
        await manager.grant('essential');
        expect(await manager.history(), isEmpty);
        expect(
          () => manager.withdraw('essential'),
          throwsA(isA<ConsentException>()),
        );
      },
    );

    test('unknown purposes are rejected and nothing is stored', () async {
      await expectLater(
        manager.update({'analytics': true, 'nope': true}),
        throwsA(isA<ConsentException>()),
      );
      expect(await manager.history(), isEmpty);
      expect(() => manager.watch('nope'), throwsA(isA<ConsentException>()));
    });

    test('a failed call does not block later calls', () async {
      await expectLater(
        manager.withdraw('essential'),
        throwsA(isA<ConsentException>()),
      );
      await manager.grant('analytics');
      expect(manager.isGranted('analytics'), isTrue);
    });

    test('changes and watch emit immediately', () async {
      final states = <ConsentState>[];
      final sub = manager.changes.listen(states.add);
      final watched = <bool>[];
      final watchSub = manager.watch('analytics').listen(watched.add);
      await Future<void>.delayed(Duration.zero);

      await manager.grant('analytics');
      await manager.grant('marketing');
      await manager.withdraw('analytics');
      await Future<void>.delayed(Duration.zero);

      expect(watched, [false, true, false]);
      expect(states, hasLength(3));
      await sub.cancel();
      await watchSub.cancel();
    });

    test('concurrent updates are serialized', () async {
      await Future.wait([
        manager.grant('analytics'),
        manager.withdraw('analytics'),
        manager.grant('analytics'),
      ]);
      final history = await manager.history();
      expect(history.map((r) => r.granted), [true, false, true]);
      expect(manager.isGranted('analytics'), isTrue);
    });

    test('dispose closes the change stream', () async {
      final done = Completer<void>();
      manager.changes.listen(null, onDone: done.complete);
      await manager.dispose();
      await done.future;
    });
  });

  group('policy version changes', () {
    test('consent from an older version must be asked again', () async {
      final store = InMemoryConsentStore();
      final v1 = ConsentManager(
        policy: testPolicy(version: '1'),
        store: store,
      );
      await v1.initialize();
      await v1.acceptAll();
      expect(v1.isGranted('analytics'), isTrue);

      final trail = InMemoryAuditTrail();
      final v2 = ConsentManager(
        policy: testPolicy(version: '2'),
        store: store,
        auditTrail: trail,
      );
      await v2.initialize();
      expect(v2.state.status, ConsentStatus.policyChanged);
      expect(v2.state.previousPolicyVersion, '1');
      expect(v2.state.needsConsent, isTrue);
      expect(v2.isGranted('analytics'), isFalse);
      expect(v2.state.hasDecided('analytics'), isFalse);

      await Future<void>.delayed(Duration.zero);
      expect(trail.history.single.type, 'consent_policy_changed');
      expect(trail.history.single.metadata, {
        'previous_version': '1',
        'policy_version': '2',
      });

      await v2.acceptAll();
      expect(v2.state.status, ConsentStatus.upToDate);
      expect(v2.state.hasDecided('analytics'), isTrue);
    });

    test('a policy with no optional purposes is always up to date', () async {
      final manager = ConsentManager(
        policy: ConsentPolicy(
          version: '1',
          purposes: [
            ConsentPurpose(
              id: 'essential',
              title: 't',
              description: 'd',
              required: true,
            ),
          ],
        ),
      );
      await manager.initialize();
      expect(manager.state.status, ConsentStatus.upToDate);
    });
  });

  test('a failing audit trail does not block consent changes', () async {
    final manager = ConsentManager(
      policy: testPolicy(version: '2'),
      store: InMemoryConsentStore([
        ConsentRecord(
          purposeId: 'analytics',
          granted: true,
          timestamp: DateTime.utc(2026),
          policyVersion: '1',
        ),
      ]),
      auditTrail: _FailingTrail(),
    );
    await manager.initialize();
    await manager.grant('analytics');
    expect(manager.isGranted('analytics'), isTrue);
  });

  test('InMemoryConsentStore clear', () async {
    final store = InMemoryConsentStore();
    await store.append([
      ConsentRecord(
        purposeId: 'a',
        granted: true,
        timestamp: DateTime.utc(2026),
        policyVersion: '1',
      ),
    ]);
    await store.clear();
    expect(await store.load(), isEmpty);
  });
}
