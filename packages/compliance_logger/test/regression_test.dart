import 'dart:async';

import 'package:compliance_logger/compliance_logger.dart';
import 'package:test/test.dart';

// Regression tests for redaction bypasses found in review. All values are
// fake; credential-shaped strings are assembled at runtime.

String _fake(List<String> parts) => parts.join();

class _ThrowingToString {
  @override
  String toString() => throw StateError('boom jane.doe@example.com');
}

void main() {
  final redactor = Redactor();
  String redact(String input) => redactor.redact(input).text;

  void expectMasked(String input, String secret) {
    final out = redact(input);
    expect(out, isNot(contains(secret)), reason: '"$input" -> "$out"');
  }

  group('sensitive fields inside other values', () {
    for (final input in [
      'Error: password=hunter2',
      'Login failed:password=hunter2',
      'user=jane|password=hunter2',
      'cb=https://app.example.com/x?token=hunter2',
      '{"note":"password=hunter2"}',
    ]) {
      test(input, () => expectMasked(input, 'hunter2'));
    }
  });

  group('sensitive field value shapes', () {
    for (final input in [
      'password=hun{ter2}',
      'password=ab;cd,ef',
      'password="hunter2',
      "password => 'hunter2'",
      'user[password]=hunter2',
      '"password": ["hunter2"]',
      '"password": {"v": "hunter2"}',
    ]) {
      test(input, () {
        final out = redact(input);
        for (final part in ['hunter2', 'ter2', 'cd', 'ef']) {
          if (input.contains(part)) {
            expect(out, isNot(contains(part)), reason: '"$input" -> "$out"');
          }
        }
      });
    }

    test('query strings still keep the other parameters', () {
      expect(
        redact('GET /login?user=test&password=hunter2&x=1'),
        'GET /login?user=test&password=[REDACTED:sensitive_field]&x=1',
      );
    });
  });

  group('more sensitive key names', () {
    test('map keys', () {
      final out = redactor.redactValue({
        'pin_code': '1234',
        'cardCvv': '123',
        'passcode': '9999',
        'pass': 'hunter2',
        'authCode': 'x',
        'mnemonic': 'word word',
      });
      expect((out! as Map).values.toSet(), {Redactor.sensitiveKeyMask});
    });

    test('text form', () {
      final out = redact(
        'passcode=1234 pin_code=1234 cvv2=123 otpCode=123456 pass=hunter2',
      );
      expect(out, isNot(contains('1234')));
      expect(out, isNot(contains('123456')));
      expect(out, isNot(contains('hunter2')));
    });
  });

  group('api keys', () {
    test('keys before a PEM block are still masked', () {
      final aws = _fake(['AK', 'IA', 'IOSFODNN7EXAMPLE']);
      final gh = _fake(['gh', 'p_', 'aBcD1234' * 5]);
      final pem = _fake([
        '-----BEGIN PRIVATE',
        ' KEY-----\nFAKE\n',
        '-----END PRIVATE',
        ' KEY-----',
      ]);
      final out = redact('aws $aws token $gh\n$pem');
      expect(out, isNot(contains(aws)));
      expect(out, isNot(contains(gh)));
      expect(out, isNot(contains('FAKE')));
    });

    test('a truncated PEM block is masked to the end', () {
      final pem = _fake(['-----BEGIN PRIVATE', ' KEY-----\nAbC9xYz\nMore']);
      final out = redact('key $pem');
      expect(out, 'key [REDACTED:api_key]');
    });

    test('PEM scanning is linear', () {
      final input = _fake(['-----BEGIN PRIVATE', ' KEY-----']) * 20000;
      final watch = Stopwatch()..start();
      redact(input);
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });

    test('generic key after "=" is masked', () {
      final key = _fake(['Q2xhaW1zR2VuZXJpY0tl', 'eTEyMzQ1Njc4OTBhYmNk']);
      expectMasked('blob=$key', key);
    });
  });

  group('cards and phones in more contexts', () {
    for (final input in [
      'card:4111111111111111',
      'GET /cards/4111111111111111',
      'card 4111 1111 1111 1111 123',
      'card 4111111111111111 123',
    ]) {
      test(input, () {
        final out = redact(input);
        expect(out, isNot(contains('1111 1111')), reason: out);
        expect(out, isNot(contains('4111111111111111')), reason: out);
      });
    }

    for (final input in [
      'tel:+442079460958',
      'phone:+44 20 7946 0958',
      'Room 3 +44 20 7946 0958',
    ]) {
      test(input, () {
        expect(redact(input), isNot(contains('7946')));
      });
    }
  });

  group('iban and email variants', () {
    test('lowercase IBAN', () {
      expect(
        redact('iban de89 3704 0044 0532 0130 00'),
        'iban [REDACTED:iban]',
      );
    });

    for (final input in [
      'mail jäne@exämple.com',
      'email=jane.doe%40example.com',
      'id jane.doe@example.com-x',
    ]) {
      test(input, () {
        final out = redact(input);
        expect(out, isNot(contains('jane')), reason: out);
        expect(out, isNot(contains('jäne')), reason: out);
      });
    }
  });

  test('partial mask of an encoded email', () {
    final r = Redactor(rules: [const EmailRule(mode: MaskMode.partial)]);
    expect(r.redact('to=jane.doe%40example.com').text, 'to=j***@example.com');
  });

  group('authorization header shapes', () {
    for (final input in [
      'Authorization: Bearer "abc12345xyz"',
      'Authorization: Bearer\nabc12345xyz',
      'Authorization: Digest username="jane", realm="x"',
      'Bearer abcdefghijklmnopqrstuvwxyzABCDEF',
    ]) {
      test(input.replaceAll('\n', r'\n'), () {
        final out = redact(input);
        expect(out, isNot(contains('abc')), reason: out);
        expect(out, isNot(contains('jane')), reason: out);
      });
    }
  });

  group('logger never throws or leaks', () {
    late MemorySink sink;
    late ComplianceLogger log;

    setUp(() {
      sink = MemorySink();
      log = ComplianceLogger(sinks: [sink]);
    });

    test('throwing lazy message', () {
      log.info(() => throw StateError('msg jane.doe@example.com'));
      expect(sink.messages.single, Redactor.failureMask);
    });

    test('throwing toString in message, error, fields and keys', () {
      log
        ..info(_ThrowingToString())
        ..info('x', error: _ThrowingToString())
        ..info('x', fields: {'a': _ThrowingToString()})
        ..info(
          'x',
          fields: {
            'n': {_ThrowingToString(): 1},
          },
        );
      expect(sink.records, hasLength(4));
      expect(sink.records[0].message, Redactor.failureMask);
      expect(sink.records[1].error, Redactor.failureMask);
      expect(sink.records[2].fields, {'a': Redactor.failureMask});
      expect(sink.records[3].fields.toString(), isNot(contains('jane')));
    });

    test('throwing onSinkError does not stop other sinks', () {
      final second = MemorySink();
      ComplianceLogger(
        sinks: [CallbackSink((_) => throw StateError('sink')), second],
        onSinkError: (_, _) => throw StateError('handler'),
      ).info('hello');
      expect(second.messages, ['hello']);
    });

    test('async sink errors go to onSinkError', () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        ComplianceLogger(
          sinks: [CallbackSink((_) async => throw StateError('async sink'))],
          onSinkError: (e, _) => errors.add(e),
        ).info('x');
        await Future<void>.delayed(Duration.zero);
      }, (e, _) => fail('uncaught: $e'));
      expect(errors.single, isA<StateError>());
    });

    test('close continues after a throwing sink', () async {
      var closed = false;
      await ComplianceLogger(
        sinks: [
          CallbackSink((_) {}, onClose: () async => throw StateError('x')),
          CallbackSink((_) {}, onClose: () async => closed = true),
        ],
      ).close();
      expect(closed, isTrue);
    });

    test('non-finite doubles do not drop console output', () {
      final lines = <String>[];
      ComplianceLogger(
        sinks: [ConsoleSink(writer: lines.add)],
      ).info('x', fields: {'v': double.nan});
      expect(lines, hasLength(1));
    });
  });

  group('structured values', () {
    test('colliding redacted keys keep both values', () {
      final out =
          redactor.redactValue({
                'jane.doe@example.com': 'a',
                'john.doe@example.com': 'b',
              })!
              as Map;
      expect(out.values.toSet(), {'a', 'b'});
    });

    test('truncation and depth limits are counted', () {
      final counts = <String, int>{};
      Redactor(maxCollectionLength: 2, maxDepth: 2).redactValue({
        'list': [1, 2, 3],
        'deep': {
          'a': {'b': 1},
        },
      }, counts: counts);
      expect(counts[Redactor.truncatedRuleId], 1);
      expect(counts[Redactor.maxDepthRuleId], 1);
    });

    test('very long iterables are truncated', () {
      final out =
          Redactor(
                maxCollectionLength: 3,
              ).redactValue(Iterable<int>.generate(1 << 30))!
              as List;
      expect(out, [0, 1, 2, Redactor.truncatedMask]);
    });
  });
}
