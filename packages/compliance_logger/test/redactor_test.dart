import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_logger/compliance_logger.dart';
import 'package:test/test.dart';

class _ThrowingRule extends RedactionRule {
  const _ThrowingRule() : super(id: 'throwing');

  @override
  Iterable<RedactionSpan> findSpans(String input) => throw StateError('boom');
}

class _BadSpanRule extends RedactionRule {
  const _BadSpanRule() : super(id: 'bad_span');

  @override
  Iterable<RedactionSpan> findSpans(String input) => [
    const RedactionSpan(start: 0, end: 3, value: 'zzz'),
  ];
}

final _key = List<int>.generate(32, (i) => i);

void main() {
  group('Redactor', () {
    test('counts per rule and total', () {
      final result = Redactor().redact(
        'mail jane@example.com and john@example.com, card 4111111111111111',
      );
      expect(result.counts, {'email': 2, 'credit_card': 1});
      expect(result.total, 3);
      expect(result.failed, isFalse);
    });

    test('returns input unchanged when nothing matches or input is empty', () {
      final redactor = Redactor();
      expect(redactor.redact('').text, '');
      expect(redactor.redact('hello').text, 'hello');
      expect(redactor.redact('hello').counts, isEmpty);
    });

    test('masked text is not processed by later rules', () {
      // The partial email mask keeps the domain; the IP rule must not touch
      // the hash, and the hash must not be re-masked by the phone rule.
      final redactor = Redactor(
        rules: BuiltInRules.defaults(
          email: const RuleSettings(mode: MaskMode.hash),
          ipAddress: const RuleSettings(),
        ),
        hashKey: _key,
      );
      final out = redactor.redact('jane@example.com').text;
      expect(out, matches(RegExp(r'^\[HASH:email:[0-9a-f]{12}\]$')));
    });

    test('hash mode is stable per key and differs between keys', () {
      final rules = [const EmailRule(mode: MaskMode.hash)];
      final a = Redactor(rules: rules, hashKey: _key);
      final b = Redactor(rules: rules, hashKey: _key);
      final c = Redactor(rules: rules, hashKey: List.filled(32, 7));
      const input = 'jane@example.com';
      expect(a.redact(input).text, b.redact(input).text);
      expect(a.redact(input).text, isNot(c.redact(input).text));
      expect(a.redact(input).text, isNot(a.redact('john@example.com').text));
    });

    test('random hash key is stable within one redactor', () {
      final r = Redactor(rules: [const EmailRule(mode: MaskMode.hash)]);
      expect(r.redact('a@b.io').text, r.redact('a@b.io').text);
    });

    test('rejects short hash keys, bad ids, duplicates and maxDepth', () {
      Matcher invalid() => throwsA(isA<InvalidConfigurationException>());
      expect(() => Redactor(hashKey: [1, 2, 3]), invalid());
      expect(
        () => Redactor(
          customRules: [RegexRedactionRule(id: 'Bad Id', pattern: RegExp('x'))],
        ),
        invalid(),
      );
      expect(
        () => Redactor(
          customRules: [RegexRedactionRule(id: 'a' * 49, pattern: RegExp('x'))],
        ),
        invalid(),
      );
      expect(
        () => Redactor(
          customRules: [RegexRedactionRule(id: 'email', pattern: RegExp('x'))],
        ),
        invalid(),
      );
      expect(() => Redactor(maxDepth: 0), invalid());
    });

    test('disabled rules do not run', () {
      final redactor = Redactor(
        rules: BuiltInRules.defaults(email: RuleSettings.disabled),
      );
      expect(redactor.redact('jane@example.com').text, 'jane@example.com');
      expect(
        Redactor(rules: const []).redact('jane@example.com').text,
        'jane@example.com',
      );
    });

    test('allowlist and allow patterns', () {
      final redactor = Redactor(
        allowlist: {'support@example.com'},
        allowPatterns: [RegExp(r'.*@example\.org')],
      );
      expect(
        redactor.redact('mail support@example.com or jane@example.com').text,
        'mail support@example.com or [REDACTED:email]',
      );
      expect(redactor.redact('team@example.org').text, 'team@example.org');
      expect(
        redactor.redact('team@example.org.evil.io').text,
        '[REDACTED:email]',
      );
    });

    test('a throwing rule fails closed', () {
      final redactor = Redactor(customRules: [const _ThrowingRule()]);
      final result = redactor.redact('jane@example.com wrote this');
      expect(result.text, Redactor.failureMask);
      expect(result.failed, isTrue);
      expect(result.counts, {Redactor.failureRuleId: 1});
    });

    test('an inconsistent span fails closed', () {
      final redactor = Redactor(rules: [const _BadSpanRule()]);
      expect(redactor.redact('abcdef').text, Redactor.failureMask);
    });

    test('overlapping spans keep the earliest and longest', () {
      final redactor = Redactor(
        rules: [
          FunctionRedactionRule(
            id: 'overlap',
            find: (input) => const [
              RedactionSpan(start: 2, end: 4, value: 'cd'),
              RedactionSpan(start: 0, end: 3, value: 'abc'),
              RedactionSpan(start: 0, end: 2, value: 'ab'),
            ],
          ),
        ],
      );
      expect(redactor.redact('abcdef').text, '[REDACTED:overlap]def');
    });
  });

  group('custom rules', () {
    test('regex rule masks whole match', () {
      final redactor = Redactor(
        customRules: [
          RegexRedactionRule(id: 'employee_id', pattern: RegExp(r'EMP-\d{6}')),
        ],
      );
      expect(
        redactor.redact('by EMP-123456').text,
        'by [REDACTED:employee_id]',
      );
    });

    test('regex rule with named groups keeps context', () {
      final rule = RegexRedactionRule(
        id: 'employee_id',
        pattern: RegExp(r'(?<prefix>emp=)(?<value>\d{6})(?<suffix>;)'),
        partial: (v) => '${v.substring(0, 2)}****',
        mode: MaskMode.partial,
      );
      expect(Redactor(rules: [rule]).redact('emp=123456;').text, 'emp=12****;');
    });

    test('regex rule with mismatched groups masks the whole match', () {
      final rule = RegexRedactionRule(
        id: 'emp',
        pattern: RegExp(r'id (?<value>\d+)'),
      );
      expect(
        Redactor(rules: [rule]).redact('x id 42').text,
        'x [REDACTED:emp]',
      );
    });

    test('regex rule validator and empty matches', () {
      final rule = RegexRedactionRule(
        id: 'even',
        pattern: RegExp(r'\d*'),
        validator: (v) => int.parse(v).isEven,
      );
      expect(
        Redactor(rules: [rule]).redact('1 2 3 4').text,
        '1 [REDACTED:even] 3 [REDACTED:even]',
      );
      expect(rule.partialMask('2'), rule.fullMask);
    });

    test('function rule', () {
      final rule = FunctionRedactionRule(
        id: 'secret_word',
        mode: MaskMode.partial,
        partial: (v) => '${v[0]}…',
        find: (input) sync* {
          final i = input.indexOf('swordfish');
          if (i >= 0) {
            yield RedactionSpan(start: i, end: i + 9, value: 'swordfish');
          }
        },
      );
      expect(Redactor(rules: [rule]).redact('the swordfish').text, 'the s…');
      const plain = FunctionRedactionRule(id: 'p', find: _none);
      expect(plain.partialMask('x'), '[REDACTED:p]');
    });
  });

  group('redactValue', () {
    final redactor = Redactor();

    test('redacts nested maps and lists', () {
      final counts = <String, int>{};
      final out = redactor.redactValue({
        'user': {
          'email': 'jane@example.com',
          'password': 'hunter2',
          'tags': ['a', 'call +44 20 7946 0958'],
          'pin': 1234,
        },
        'card': 4111111111111111,
        'count': 3,
        'ratio': 0.5,
        'ok': true,
        'none': null,
        'set': {'jane@example.com'},
      }, counts: counts);
      expect(out, {
        'user': {
          'email': '[REDACTED:email]',
          'password': Redactor.sensitiveKeyMask,
          'tags': ['a', 'call [REDACTED:phone]'],
          'pin': Redactor.sensitiveKeyMask,
        },
        'card': '[REDACTED:credit_card]',
        'count': 3,
        'ratio': 0.5,
        'ok': true,
        'none': null,
        'set': ['[REDACTED:email]'],
      });
      expect(counts, {
        'email': 2,
        'sensitive_key': 2,
        'phone': 1,
        'credit_card': 1,
      });
    });

    test('redacts map keys and arbitrary objects', () {
      final out = redactor.redactValue({
        'jane@example.com': 1,
        'obj': Uri.parse('mailto:jane@example.com'),
      });
      expect(out, {'[REDACTED:email]': 1, 'obj': 'mailto:[REDACTED:email]'});
    });

    test('handles cycles and depth limits', () {
      final cyclic = <String, Object?>{'a': 1};
      cyclic['self'] = cyclic;
      expect(redactor.redactValue(cyclic), {
        'a': 1,
        'self': Redactor.cycleMask,
      });

      final shallow = Redactor(maxDepth: 2);
      expect(
        shallow.redactValue({
          'a': {
            'b': {'c': 1},
          },
        }),
        {
          'a': {'b': Redactor.maxDepthMask},
        },
      );
    });

    test('the same list twice is not a cycle', () {
      final shared = ['x'];
      expect(redactor.redactValue([shared, shared]), [
        ['x'],
        ['x'],
      ]);
    });

    test('a throwing rule fails closed for each string', () {
      final failing = Redactor(customRules: [const _ThrowingRule()]);
      final counts = <String, int>{};
      expect(failing.redactValue(['x', 'y'], counts: counts), [
        Redactor.failureMask,
        Redactor.failureMask,
      ]);
      expect(counts, {Redactor.failureRuleId: 2});
    });
  });
}

Iterable<RedactionSpan> _none(String input) => const [];
