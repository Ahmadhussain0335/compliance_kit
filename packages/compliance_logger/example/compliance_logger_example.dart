// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_logger/compliance_logger.dart';

Future<void> main() async {
  final audit = InMemoryAuditTrail(maxEvents: 500);

  final logger = ComplianceLogger(
    name: 'example',
    minLevel: LogLevel.debug,
    redactor: Redactor(
      rules: BuiltInRules.defaults(
        email: const RuleSettings(mode: MaskMode.partial),
        phone: const RuleSettings(mode: MaskMode.hash),
        ipAddress: const RuleSettings(),
      ),
      customRules: [
        RegexRedactionRule(id: 'customer_id', pattern: RegExp(r'CUST-\d{8}')),
      ],
      allowlist: {'support@example.com'},
      // In a real app, load a key from secure storage so hashes stay
      // comparable across restarts. Never hard-code it.
      hashKey: utf8.encode('example-only-key-do-not-reuse!!'),
    ),
    sinks: [
      const ConsoleSink(),
      CallbackSink((record) {
        if (record.level.isAtLeast(LogLevel.error)) {
          // Forward to a crash reporter here. The record is already redacted.
        }
      }),
    ],
    auditTrail: audit,
  );

  logger
    ..info('Signup by jane.doe@example.com, contact support@example.com')
    ..info('Callback number +44 20 7946 0958 for CUST-12345678')
    ..debug('Request from 203.0.113.7 with Authorization: Bearer abc123def456')
    ..warning(
      'Payment details updated',
      fields: {
        'card': '4111 1111 1111 1111',
        'iban': 'DE89 3704 0044 0532 0130 00',
        'password': 'not-a-real-password',
      },
    );

  try {
    throw const FormatException('Bad input from jane.doe@example.com');
  } on FormatException catch (e, st) {
    logger.error('Parsing failed', error: e, stackTrace: st);
  }

  await Future<void>.delayed(Duration.zero);
  print('\nAudit events (counts only):');
  for (final event in audit.history) {
    print(event.metadata);
  }
  await audit.dispose();
}
