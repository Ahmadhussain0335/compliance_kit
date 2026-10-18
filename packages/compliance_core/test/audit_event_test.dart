import 'package:compliance_core/compliance_core.dart';
import 'package:test/test.dart';

void main() {
  group('AuditEvent', () {
    test('stores fields and converts timestamp to UTC', () {
      final local = DateTime(2026, 1, 2, 3, 4, 5);
      final event = AuditEvent(
        type: 'consent_granted',
        source: 'compliance_gdpr',
        timestamp: local,
        metadata: const {'purpose': 'analytics', 'count': 1},
      );
      expect(event.type, 'consent_granted');
      expect(event.source, 'compliance_gdpr');
      expect(event.timestamp.isUtc, isTrue);
      expect(event.timestamp, local.toUtc());
      expect(event.metadata, {'purpose': 'analytics', 'count': 1});
    });

    test('defaults timestamp to now in UTC', () {
      final before = DateTime.now().toUtc();
      final event = AuditEvent(type: 'x', source: 'y');
      final after = DateTime.now().toUtc();
      expect(event.timestamp.isUtc, isTrue);
      expect(event.timestamp.isBefore(before), isFalse);
      expect(event.timestamp.isAfter(after), isFalse);
      expect(event.metadata, isEmpty);
    });

    test('metadata is unmodifiable and copied', () {
      final source = <String, Object?>{'a': 1};
      final event = AuditEvent(type: 'x', source: 'y', metadata: source);
      source['b'] = 2;
      expect(event.metadata.containsKey('b'), isFalse);
      expect(() => event.metadata['c'] = 3, throwsUnsupportedError);
    });

    test('accepts all primitive metadata types', () {
      final event = AuditEvent(
        type: 'x',
        source: 'y',
        metadata: const {'s': 'v', 'i': 1, 'd': 1.5, 'b': true, 'n': null},
      );
      expect(event.metadata, hasLength(5));
    });

    group('rejects', () {
      Matcher invalid() => throwsA(isA<InvalidAuditEventException>());

      test('empty, uppercase or long identifiers', () {
        expect(() => AuditEvent(type: '', source: 'y'), invalid());
        expect(() => AuditEvent(type: 'Consent', source: 'y'), invalid());
        expect(() => AuditEvent(type: '1abc', source: 'y'), invalid());
        expect(() => AuditEvent(type: 'a b', source: 'y'), invalid());
        expect(() => AuditEvent(type: 'x', source: ''), invalid());
        expect(() => AuditEvent(type: 'a' * 65, source: 'y'), invalid());
        expect(AuditEvent(type: 'a' * 64, source: 'y').type, hasLength(64));
      });

      test('nested, object and non-finite metadata values', () {
        expect(
          () => AuditEvent(
            type: 'x',
            source: 'y',
            metadata: const {
              'user': {'email': 'jane.doe@example.com'},
            },
          ),
          invalid(),
        );
        expect(
          () => AuditEvent(
            type: 'x',
            source: 'y',
            metadata: const {
              'ids': [1, 2],
            },
          ),
          invalid(),
        );
        expect(
          () => AuditEvent(
            type: 'x',
            source: 'y',
            metadata: {'when': DateTime.utc(2026)},
          ),
          invalid(),
        );
        expect(
          () => AuditEvent(
            type: 'x',
            source: 'y',
            metadata: const {'ratio': double.nan},
          ),
          invalid(),
        );
      });

      test('error message does not echo the rejected value', () {
        try {
          AuditEvent(
            type: 'x',
            source: 'y',
            metadata: {
              'user': ['jane.doe@example.com'],
            },
          );
          fail('expected exception');
        } on InvalidAuditEventException catch (e) {
          expect(e.message, isNot(contains('jane.doe')));
          expect(e.toString(), isNot(contains('jane.doe')));
        }
      });

      test('long strings, bad keys and too many entries', () {
        expect(
          () =>
              AuditEvent(type: 'x', source: 'y', metadata: {'note': 'a' * 257}),
          invalid(),
        );
        expect(
          AuditEvent(
            type: 'x',
            source: 'y',
            metadata: {'note': 'a' * 256},
          ).metadata['note'],
          hasLength(256),
        );
        expect(
          () => AuditEvent(type: 'x', source: 'y', metadata: const {'': 1}),
          invalid(),
        );
        expect(
          () => AuditEvent(
            type: 'x',
            source: 'y',
            metadata: const {'bad key': 1},
          ),
          invalid(),
        );
        expect(
          () => AuditEvent(
            type: 'x',
            source: 'y',
            metadata: {for (var i = 0; i < 33; i++) 'k$i': i},
          ),
          invalid(),
        );
      });
    });

    group('JSON', () {
      test('round-trips', () {
        final event = AuditEvent(
          type: 'log_redaction',
          source: 'compliance_logger',
          timestamp: DateTime.utc(2026, 5, 6, 7, 8, 9, 10),
          metadata: const {'total': 2, 'email': 1, 'ok': true},
        );
        final json = event.toJson();
        expect(json['timestamp'], '2026-05-06T07:08:09.010Z');
        expect(AuditEvent.fromJson(json), event);
      });

      test('missing metadata decodes as empty', () {
        final event = AuditEvent.fromJson(const {
          'type': 'x',
          'source': 'y',
          'timestamp': '2026-01-01T00:00:00.000Z',
        });
        expect(event.metadata, isEmpty);
      });

      test('rejects malformed input', () {
        Matcher invalid() => throwsA(isA<InvalidAuditEventException>());
        expect(() => AuditEvent.fromJson(const {}), invalid());
        expect(
          () => AuditEvent.fromJson(const {
            'type': 'x',
            'source': 'y',
            'timestamp': 'not a date',
          }),
          invalid(),
        );
        expect(
          () => AuditEvent.fromJson(const {
            'type': 'x',
            'source': 'y',
            'timestamp': '2026-01-01T00:00:00Z',
            'metadata': 'nope',
          }),
          invalid(),
        );
        expect(
          () => AuditEvent.fromJson(const {
            'type': 'x',
            'source': 'y',
            'timestamp': '2026-01-01T00:00:00Z',
            'metadata': {1: 'a'},
          }),
          invalid(),
        );
      });
    });

    group('equality', () {
      final t = DateTime.utc(2026);
      AuditEvent make({Map<String, Object?> metadata = const {'a': 1}}) =>
          AuditEvent(type: 'x', source: 'y', timestamp: t, metadata: metadata);

      test('equal events have equal hash codes', () {
        expect(make(), make());
        expect(make().hashCode, make().hashCode);
        final a = make();
        expect(a == a, isTrue);
      });

      test('differs on metadata', () {
        expect(make(), isNot(make(metadata: const {'a': 2})));
        expect(make(), isNot(make(metadata: const {'b': 1})));
        expect(make(), isNot(make(metadata: const {'a': 1, 'b': 1})));
        expect(make(), isNot(AuditEvent(type: 'z', source: 'y', timestamp: t)));
        expect(make() == Object(), isFalse);
      });

      test('toString includes type and source', () {
        expect(make().toString(), contains('type: x'));
        expect(make().toString(), contains('source: y'));
      });
    });
  });
}
