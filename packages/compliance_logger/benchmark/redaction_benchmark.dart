// Simple wall-clock benchmark for the redactor and logger.
//
// Run with: dart run benchmark/redaction_benchmark.dart
// For stable numbers, compile first: dart compile exe benchmark/redaction_benchmark.dart
// ignore_for_file: avoid_print

import 'package:compliance_logger/compliance_logger.dart';

void main() {
  final redactor = Redactor(hashKey: List<int>.generate(32, (i) => i));
  final logger = ComplianceLogger(sinks: [_NullSink()], redactor: redactor);

  const clean = 'User opened settings screen, build 1.2.3, took 42 ms';
  const withPii =
      'Login failed for jane.doe@example.com from +44 20 7946 0958, '
      'Authorization: Bearer abcdef0123456789abcdef, card 4111 1111 1111 1111';
  final longText = List.filled(64, clean).join(' | ');
  final fields = <String, Object?>{
    'user': {'email': 'jane.doe@example.com', 'password': 'not-real'},
    'items': [1, 2, 3, 'order ORD-2026-000123'],
    'iban': 'DE89 3704 0044 0532 0130 00',
  };

  print('compliance_logger benchmark (${_mode()})');
  print('${'case'.padRight(36)} ${'us/op'.padLeft(10)} ${'ops/s'.padLeft(12)}');
  _run('redact: clean short message', () => redactor.redact(clean));
  _run('redact: message with 4 PII values', () => redactor.redact(withPii));
  _run('redact: clean 3.5 KB message', () => redactor.redact(longText));
  _run('redactValue: nested map', () => redactor.redactValue(fields));
  _run('logger.info: message with PII', () => logger.info(withPii));
}

void _run(String name, void Function() body) {
  for (var i = 0; i < 2000; i++) {
    body();
  }
  const iterations = 20000;
  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  watch.stop();
  final usPerOp = watch.elapsedMicroseconds / iterations;
  print(
    '${name.padRight(36)} ${usPerOp.toStringAsFixed(2).padLeft(10)} '
    '${(1e6 / usPerOp).toStringAsFixed(0).padLeft(12)}',
  );
}

String _mode() => const bool.fromEnvironment('dart.vm.product') ? 'AOT' : 'JIT';

final class _NullSink extends LogSink {
  @override
  void write(LogRecord record) {}
}
