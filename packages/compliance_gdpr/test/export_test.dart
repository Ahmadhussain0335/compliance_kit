import 'dart:async';
import 'dart:convert';

import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_gdpr/compliance_gdpr.dart';
import 'package:compliance_logger/compliance_logger.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _FailingTrail implements AuditTrail {
  @override
  Stream<AuditEvent> get events => const Stream.empty();

  @override
  Future<void> record(AuditEvent event) => Future.error(StateError('down'));
}

void main() {
  late InMemoryAuditTrail trail;
  late DataExporter exporter;

  setUp(() {
    trail = InMemoryAuditTrail();
    exporter = DataExporter(
      appId: 'com.example.app',
      auditTrail: trail,
      clock: () => DateTime.utc(2026, 10, 18, 12, 0, 0, 123),
      sourceTimeout: const Duration(milliseconds: 100),
    );
  });

  test('exports every source into one JSON document', () async {
    exporter
      ..register(
        CallbackDataSource(
          'profile',
          () async => {'name': 'Test User', 'email': 'test.user@example.com'},
        ),
      )
      ..register(CallbackDataSource('settings', () async => ['dark_mode']));

    final progress = <ExportProgress>[];
    final export = await exporter.export(onProgress: progress.add);

    expect(export.isComplete, isTrue);
    expect(export.failures, isEmpty);
    expect(progress.map((p) => p.fraction), [0.5, 1.0]);
    expect(progress.last.sourceId, 'settings');

    final json = jsonDecode(export.toJsonString()) as Map<String, Object?>;
    expect(json['schema_version'], 1);
    expect(json['app_id'], 'com.example.app');
    expect(json['export_date'], '2026-10-18T12:00:00.123Z');
    expect(json['complete'], true);
    expect(json['sources'], ['profile', 'settings']);
    expect(json['data'], {
      'profile': {
        'status': 'ok',
        'data': {'name': 'Test User', 'email': 'test.user@example.com'},
      },
      'settings': {
        'status': 'ok',
        'data': ['dark_mode'],
      },
    });
    expect(export.toJsonString(pretty: false), isNot(contains('\n')));
    expect(
      export.suggestedFileName,
      'com.example.app-data-export-20261018T120000Z.json',
    );
  });

  test('a failing source is reported without failing the export', () async {
    exporter
      ..register(CallbackDataSource('ok', () async => 1))
      ..register(
        CallbackDataSource('broken', () async => throw StateError('db closed')),
      )
      ..register(
        CallbackDataSource(
          'slow',
          () => Future<Object?>.delayed(const Duration(seconds: 5), () => 1),
        ),
      )
      ..register(CallbackDataSource('weird', () async => DateTime.utc(2026)));

    final export = await exporter.export();
    expect(export.isComplete, isFalse);
    expect(export.results.map((r) => r.status), [
      SourceExportStatus.success,
      SourceExportStatus.failed,
      SourceExportStatus.timedOut,
      SourceExportStatus.notSerializable,
    ]);
    expect(export.results[1].error, isA<StateError>());
    expect(export.results[1].stackTrace, isNotNull);
    expect(export.failures.map((r) => r.sourceId), ['broken', 'slow', 'weird']);

    final data = (jsonDecode(export.toJsonString()) as Map)['data'] as Map;
    expect(data['broken'], {'status': 'failed'});
    expect(data['slow'], {'status': 'timed_out'});
    expect(data['weird'], {'status': 'not_serializable'});
    expect(export.toJsonString(), isNot(contains('db closed')));

    await Future<void>.delayed(Duration.zero);
    expect(trail.history.single.type, 'data_exported');
    expect(trail.history.single.metadata, {
      'sources': 4,
      'failed': 3,
      'complete': false,
    });
  });

  test('empty export', () async {
    final export = await exporter.export();
    expect(export.isComplete, isTrue);
    expect(
      const ExportProgress(
        completed: 0,
        total: 0,
        sourceId: 'x',
        status: SourceExportStatus.success,
      ).fraction,
      1,
    );
  });

  test('registration validates ids', () {
    Matcher invalid() => throwsA(isA<InvalidConfigurationException>());
    expect(
      () => exporter.register(CallbackDataSource('Bad Id', () async => 1)),
      invalid(),
    );
    exporter.register(CallbackDataSource('a', () async => 1));
    expect(
      () => exporter.register(CallbackDataSource('a', () async => 1)),
      invalid(),
    );
    expect(exporter.sourceIds, ['a']);
    expect(exporter.unregister('a'), isTrue);
    expect(exporter.unregister('a'), isFalse);
  });

  test('redacting source removes third-party data from logs', () async {
    exporter.register(
      RedactingDataSource(
        CallbackDataSource(
          'support_log',
          () async => [
            'Ticket forwarded to agent other.person@example.com',
            {'note': 'call back +44 20 7946 0958'},
          ],
        ),
        Redactor(),
      ),
    );
    final export = await exporter.export();
    expect(export.results.single.sourceId, 'support_log');
    expect(export.results.single.data, [
      'Ticket forwarded to agent [REDACTED:email]',
      {'note': 'call back [REDACTED:phone]'},
    ]);
  });

  test('a failing audit trail does not break the export', () async {
    final export = await DataExporter(
      appId: 'a',
      auditTrail: _FailingTrail(),
      clock: steppingClock(),
    ).export();
    expect(export.isComplete, isTrue);
  });

  test('suggested file name sanitizes the app id', () {
    final export = DataExport(
      appId: 'my app/1',
      exportedAt: DateTime.utc(2026),
      results: const [],
    );
    expect(export.suggestedFileName, startsWith('my_app_1-data-export-'));
  });
}
