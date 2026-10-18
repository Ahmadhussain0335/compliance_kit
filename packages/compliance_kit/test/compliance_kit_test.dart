import 'dart:convert';

import 'package:compliance_kit/compliance_kit.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeIntegrity implements IntegrityPlatform {
  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> prepare({int? cloudProjectNumber}) async {}

  @override
  Future<PlatformToken> requestToken({
    required String requestHash,
    int? cloudProjectNumber,
  }) async => const PlatformToken(
    token: 'ZmFrZQ',
    kind: IntegrityTokenKind.playIntegrityStandard,
  );

  @override
  Future<void> reset() async {}
}

ConsentPolicy _policy() => ConsentPolicy(
  version: '1',
  purposes: [
    ConsentPurpose(
      id: 'crash_reporting',
      title: 'Crash reports',
      description: 'd',
    ),
    ConsentPurpose(id: 'analytics', title: 'Analytics', description: 'd'),
  ],
);

void main() {
  late InMemoryAuditTrail trail;
  late List<LogRecord> forwarded;
  late MemorySink memory;
  late ComplianceKit kit;

  setUp(() async {
    trail = InMemoryAuditTrail();
    forwarded = [];
    memory = MemorySink();
    kit = await ComplianceKit.init(
      appId: 'com.example.app',
      auditTrail: trail,
      logSinks: [memory],
      forwardLogs: forwarded.add,
      forwardLogsPurpose: 'crash_reporting',
      consentPolicy: _policy(),
      eraseConsentOnDeletion: true,
      integrityPlatform: _FakeIntegrity(),
    );
  });

  tearDown(() => kit.dispose());

  test('all modules record into the shared audit trail', () async {
    kit.logger.info('mail jane.doe@example.com');
    await kit.consent!.grant('analytics');
    await kit.exporter.export();
    await kit.integrity.requestToken('server-challenge');
    await kit.deletion.deleteAll(confirm: () async => true);
    await Future<void>.delayed(Duration.zero);

    final sources = trail.history.map((e) => e.source).toSet();
    expect(sources, {
      'compliance_logger',
      'compliance_gdpr',
      'compliance_integrity',
    });
    expect(
      trail.history.map((e) => e.type),
      containsAll(<String>[
        'log_redaction',
        'consent_granted',
        'data_exported',
        'integrity_check_passed',
        'data_deletion_requested',
        'data_deletion_completed',
      ]),
    );
    expect(memory.messages.single, 'mail [REDACTED:email]');
  });

  test('forwarding follows consent and level', () async {
    kit.logger.error('before consent');
    await kit.consent!.grant('crash_reporting');
    kit.logger
      ..info('below forward level')
      ..error('crash for jane.doe@example.com');
    await kit.consent!.withdraw('crash_reporting');
    kit.logger.error('after withdrawal');
    expect(forwarded.map((r) => r.message), ['crash for [REDACTED:email]']);
  });

  test('consent history is exported and erased on deletion', () async {
    await kit.consent!.grant('analytics');
    final export = await kit.exporter.export();
    final data = jsonDecode(export.toJsonString()) as Map<String, Object?>;
    final history =
        ((data['data']! as Map)['consent_history']! as Map)['data']! as List;
    expect(history.single, containsPair('purpose_id', 'analytics'));

    final report = await kit.deletion.deleteAll(confirm: () async => true);
    expect(report.local.single.id, 'consent_records');
    expect(await kit.consent!.history(), isEmpty);
    expect(kit.consent!.isGranted('analytics'), isFalse);
  });

  test('defaults without consent policy', () async {
    final minimal = await ComplianceKit.init(
      appId: 'a',
      logSinks: const [],
      forwardLogs: forwarded.add,
      integrityPlatform: _FakeIntegrity(),
    );
    expect(minimal.consent, isNull);
    expect(minimal.auditTrail, isA<InMemoryAuditTrail>());
    expect(minimal.exporter.sourceIds, isEmpty);
    expect(minimal.deletion.eraserIds, isEmpty);
    minimal.logger.warning('forwarded without a purpose');
    expect(forwarded.single.message, 'forwarded without a purpose');
    await minimal.dispose();

    final console = await ComplianceKit.init(appId: 'a');
    expect(console.logger.sinks.single, isA<ConsoleSink>());
  });

  test('opting out of consent history export', () async {
    final k = await ComplianceKit.init(
      appId: 'a',
      consentPolicy: _policy(),
      exportConsentHistory: false,
      integrityPlatform: _FakeIntegrity(),
    );
    expect(k.exporter.sourceIds, isEmpty);
    expect(k.deletion.eraserIds, isEmpty);
  });

  test('forwarding purpose must exist in the policy', () async {
    await expectLater(
      ComplianceKit.init(
        appId: 'a',
        forwardLogs: (_) {},
        forwardLogsPurpose: 'crash_reporting',
      ),
      throwsA(isA<InvalidConfigurationException>()),
    );
    await expectLater(
      ComplianceKit.init(
        appId: 'a',
        consentPolicy: _policy(),
        forwardLogs: (_) {},
        forwardLogsPurpose: 'unknown',
      ),
      throwsA(isA<InvalidConfigurationException>()),
    );
  });
}
