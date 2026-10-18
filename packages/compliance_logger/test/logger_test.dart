import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_logger/compliance_logger.dart';
import 'package:test/test.dart';

class _ThrowingRule extends RedactionRule {
  const _ThrowingRule() : super(id: 'throwing');

  @override
  Iterable<RedactionSpan> findSpans(String input) => throw StateError('boom');
}

class _FailingTrail implements AuditTrail {
  @override
  Stream<AuditEvent> get events => const Stream.empty();

  @override
  Future<void> record(AuditEvent event) => Future.error(StateError('down'));
}

class _SyncThrowingTrail implements AuditTrail {
  @override
  Stream<AuditEvent> get events => const Stream.empty();

  @override
  Future<void> record(AuditEvent event) => throw StateError('down');
}

class _CustomError implements Exception {
  @override
  String toString() => 'Login failed for jane@example.com';
}

void main() {
  final fixedTime = DateTime.utc(2026, 10, 18, 12);

  late MemorySink sink;
  late ComplianceLogger logger;

  setUp(() {
    sink = MemorySink();
    logger = ComplianceLogger(
      name: 'test',
      minLevel: LogLevel.trace,
      sinks: [sink],
      clock: () => fixedTime,
    );
  });

  group('ComplianceLogger', () {
    test('every level method writes a record at that level', () {
      logger
        ..trace('t')
        ..debug('d')
        ..info('i')
        ..warning('w')
        ..error('e')
        ..fatal('f');
      expect(sink.records.map((r) => r.level), LogLevel.values);
      expect(sink.messages, ['t', 'd', 'i', 'w', 'e', 'f']);
      expect(sink.records.first.loggerName, 'test');
      expect(sink.records.first.time, fixedTime);
    });

    test('drops records below minLevel without evaluating lazy messages', () {
      var evaluated = false;
      final quiet = ComplianceLogger(sinks: [sink], minLevel: LogLevel.warning)
        ..info(() {
          evaluated = true;
          return 'never';
        })
        ..warning(() => 'lazy jane@example.com');
      expect(evaluated, isFalse);
      expect(sink.messages, ['lazy [REDACTED:email]']);
      expect(quiet.isEnabled(LogLevel.error), isTrue);
      expect(quiet.isEnabled(LogLevel.debug), isFalse);
    });

    test('redacts message, error, stack trace and fields before sinks', () {
      final stack = StackTrace.fromString(
        '#0 handler (file.dart:1:1) user=jane@example.com',
      );
      logger.error(
        'Login failed for jane@example.com',
        error: _CustomError(),
        stackTrace: stack,
        fields: {
          'password': 'hunter2',
          'phone': '+44 20 7946 0958',
          'attempt': 2,
        },
      );
      final record = sink.records.single;
      expect(record.message, 'Login failed for [REDACTED:email]');
      expect(record.error, 'Login failed for [REDACTED:email]');
      expect(record.stackTrace, contains('user=[REDACTED:email]'));
      expect(record.fields, {
        'password': Redactor.sensitiveKeyMask,
        'phone': '[REDACTED:phone]',
        'attempt': 2,
      });
      expect(record.redactions, {'email': 3, 'sensitive_key': 1, 'phone': 1});
      expect(record.redactionCount, 5);
      expect(() => record.fields!['x'] = 1, throwsUnsupportedError);
    });

    test('a failing rule never leaks the raw message', () {
      final failing = ComplianceLogger(
        sinks: [sink],
        redactor: Redactor(customRules: [const _ThrowingRule()]),
      )..info('secret jane@example.com');
      expect(failing.sinks, hasLength(1));
      expect(sink.messages.single, Redactor.failureMask);
    });

    test('null message is logged as "null"', () {
      logger.info(null);
      expect(sink.messages, ['null']);
    });

    test('a throwing sink does not stop other sinks', () {
      final errors = <Object>[];
      final second = MemorySink();
      ComplianceLogger(
        sinks: [CallbackSink((_) => throw StateError('sink down')), second],
        onSinkError: (e, _) => errors.add(e),
      ).info('hello');
      expect(second.messages, ['hello']);
      expect(errors.single, isA<StateError>());
      ComplianceLogger(
        sinks: [CallbackSink((_) => throw StateError('sink down'))],
      ).info('ignored');
    });

    test('no sinks means nothing happens', () {
      ComplianceLogger(sinks: const []).info('x');
    });

    test('child shares configuration with a new name', () {
      final child = logger.child('child', minLevel: LogLevel.error)
        ..info('dropped')
        ..error('kept');
      expect(child.name, 'child');
      expect(child.redactor, same(logger.redactor));
      expect(sink.records.single.loggerName, 'child');
      expect(logger.child('other').minLevel, LogLevel.trace);
    });

    test('close closes every sink', () async {
      var closed = 0;
      await ComplianceLogger(
        sinks: [
          CallbackSink((_) {}, onClose: () async => closed++),
          CallbackSink((_) {}, onClose: () async => closed++),
          MemorySink(),
        ],
      ).close();
      expect(closed, 2);
    });

    test('defaults to a console sink and info level', () {
      final defaults = ComplianceLogger();
      expect(defaults.sinks.single, isA<ConsoleSink>());
      expect(defaults.minLevel, LogLevel.info);
    });
  });

  group('audit trail integration', () {
    test('records counts only, never values', () async {
      final trail = InMemoryAuditTrail();
      ComplianceLogger(
          name: 'audited',
          sinks: [sink],
          auditTrail: trail,
          clock: () => fixedTime,
        )
        ..info('nothing to see')
        ..warning('mail jane@example.com, card 4111 1111 1111 1111');
      await Future<void>.delayed(Duration.zero);

      final event = trail.history.single;
      expect(event.type, ComplianceLogger.redactionEventType);
      expect(event.source, 'compliance_logger');
      expect(event.timestamp, fixedTime);
      expect(event.metadata, {
        'level': 'warning',
        'total': 2,
        'rule.email': 1,
        'rule.credit_card': 1,
      });
      final json = event.toJson().toString();
      expect(json, isNot(contains('jane')));
      expect(json, isNot(contains('4111')));
    });

    test('records a failure event when a rule throws', () async {
      final trail = InMemoryAuditTrail();
      ComplianceLogger(
        sinks: [sink],
        auditTrail: trail,
        redactor: Redactor(customRules: [const _ThrowingRule()]),
      ).info('x');
      await Future<void>.delayed(Duration.zero);
      expect(
        trail.history.single.type,
        ComplianceLogger.redactionFailedEventType,
      );
    });

    test('caps metadata entries', () async {
      final trail = InMemoryAuditTrail();
      final rules = [
        for (var i = 0; i < 40; i++)
          RegexRedactionRule(id: 'r$i', pattern: RegExp('x$i(?!\\d)')),
      ];
      ComplianceLogger(
        sinks: [sink],
        auditTrail: trail,
        redactor: Redactor(rules: rules),
      ).info([for (var i = 0; i < 40; i++) 'x$i'].join(' '));
      await Future<void>.delayed(Duration.zero);
      expect(
        trail.history.single.metadata,
        hasLength(AuditEvent.maxMetadataEntries),
      );
    });

    test('a failing audit trail does not break logging', () async {
      ComplianceLogger(
        sinks: [sink],
        auditTrail: _FailingTrail(),
      ).info('jane@example.com');
      ComplianceLogger(
        sinks: [sink],
        auditTrail: _SyncThrowingTrail(),
      ).info('jane@example.com');
      await Future<void>.delayed(Duration.zero);
      expect(sink.messages, ['[REDACTED:email]', '[REDACTED:email]']);
    });
  });

  group('LogLevel', () {
    test('ordering and labels', () {
      expect(LogLevel.error.isAtLeast(LogLevel.warning), isTrue);
      expect(LogLevel.debug.isAtLeast(LogLevel.info), isFalse);
      expect(LogLevel.fatal.compareTo(LogLevel.trace), greaterThan(0));
      expect(LogLevel.warning.label, 'WARNING');
    });
  });

  group('sinks', () {
    LogRecord record({
      String? error,
      String? stackTrace,
      Map<String, Object?>? fields,
    }) => LogRecord(
      level: LogLevel.info,
      loggerName: 'n',
      message: 'm',
      time: fixedTime,
      error: error,
      stackTrace: stackTrace,
      fields: fields,
    );

    test('console sink default format', () {
      final lines = <String>[];
      ConsoleSink(writer: lines.add)
        ..write(record())
        ..write(record(error: 'E', stackTrace: '#0 x', fields: {'a': 1}));
      expect(lines[0], '2026-10-18T12:00:00.000Z [INFO] n: m');
      expect(
        lines[1],
        '2026-10-18T12:00:00.000Z [INFO] n: m {"a":1}\n  error: E\n#0 x',
      );
      expect(
        ConsoleSink.defaultFormat(record(fields: {})),
        isNot(contains('{')),
      );
    });

    test('console sink custom formatter and print fallback', () async {
      final lines = <String>[];
      ConsoleSink(
        writer: lines.add,
        formatter: (r) => 'custom ${r.message}',
      ).write(record());
      expect(lines, ['custom m']);
      const ConsoleSink().write(record());
      await const ConsoleSink().close();
    });

    test('memory sink cap and clear', () {
      final memory = MemorySink(maxRecords: 2)
        ..write(record())
        ..write(record())
        ..write(record());
      expect(memory.records, hasLength(2));
      memory.clear();
      expect(memory.records, isEmpty);
    });

    test('callback sink without onClose', () async {
      final seen = <LogRecord>[];
      final callback = CallbackSink(seen.add)..write(record());
      await callback.close();
      expect(seen, hasLength(1));
    });

    test('record converts time to UTC', () {
      final local = LogRecord(
        level: LogLevel.info,
        loggerName: 'n',
        message: 'm',
        time: DateTime(2026),
      );
      expect(local.time.isUtc, isTrue);
      expect(local.redactionCount, 0);
      expect(local.fields, isNull);
    });
  });
}
