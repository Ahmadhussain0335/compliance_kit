import 'package:compliance_core/compliance_core.dart';
import 'package:test/test.dart';

AuditEvent _event(String type) => AuditEvent(type: type, source: 'test');

void main() {
  group('InMemoryAuditTrail', () {
    test('records events in order and publishes them', () async {
      final trail = InMemoryAuditTrail();
      final received = <AuditEvent>[];
      final sub = trail.events.listen(received.add);

      await trail.record(_event('a'));
      await trail.record(_event('b'));
      await Future<void>.delayed(Duration.zero);

      expect(trail.history.map((e) => e.type), ['a', 'b']);
      expect(received.map((e) => e.type), ['a', 'b']);
      await sub.cancel();
      await trail.dispose();
    });

    test('supports multiple listeners', () async {
      final trail = InMemoryAuditTrail();
      final first = trail.events.first;
      final second = trail.events.first;
      await trail.record(_event('a'));
      expect((await first).type, 'a');
      expect((await second).type, 'a');
      await trail.dispose();
    });

    test('drops the oldest events beyond maxEvents', () async {
      final trail = InMemoryAuditTrail(maxEvents: 2);
      for (final t in ['a', 'b', 'c']) {
        await trail.record(_event(t));
      }
      expect(trail.history.map((e) => e.type), ['b', 'c']);
      await trail.dispose();
    });

    test('rejects a non-positive maxEvents', () {
      expect(
        () => InMemoryAuditTrail(maxEvents: 0),
        throwsA(isA<InvalidConfigurationException>()),
      );
    });

    test('history is an unmodifiable snapshot', () async {
      final trail = InMemoryAuditTrail();
      await trail.record(_event('a'));
      final snapshot = trail.history;
      expect(() => snapshot.add(_event('b')), throwsUnsupportedError);
      await trail.record(_event('b'));
      expect(snapshot, hasLength(1));
      await trail.dispose();
    });

    test('clear empties history', () async {
      final trail = InMemoryAuditTrail();
      await trail.record(_event('a'));
      trail.clear();
      expect(trail.history, isEmpty);
      await trail.dispose();
    });

    test('dispose closes the stream and blocks further records', () async {
      final trail = InMemoryAuditTrail();
      final done = trail.events.toList();
      await trail.record(_event('a'));
      await trail.dispose();
      await trail.dispose();
      expect(trail.isDisposed, isTrue);
      expect((await done).map((e) => e.type), ['a']);
      expect(
        () => trail.record(_event('b')),
        throwsA(isA<ComplianceStateException>()),
      );
    });
  });

  group('NoopAuditTrail', () {
    test('accepts events and emits nothing', () async {
      const trail = NoopAuditTrail();
      await trail.record(_event('a'));
      expect(await trail.events.toList(), isEmpty);
    });
  });

  group('ComplianceException', () {
    test('codes and toString', () {
      const cases = <ComplianceException>[
        InvalidAuditEventException('m1'),
        InvalidConfigurationException('m2', cause: 'secret-cause'),
        ComplianceStateException('m3'),
      ];
      expect(cases.map((e) => e.code), [
        'invalid_audit_event',
        'invalid_configuration',
        'invalid_state',
      ]);
      expect(
        cases[0].toString(),
        'ComplianceException[invalid_audit_event]: m1',
      );
      expect(cases[1].cause, 'secret-cause');
      expect(cases[1].toString(), isNot(contains('secret-cause')));
    });
  });
}
