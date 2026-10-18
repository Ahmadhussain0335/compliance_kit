import 'dart:async';
import 'dart:convert';

import 'package:compliance_core/compliance_core.dart';

import '../gdpr_audit_events.dart';
import 'data_source.dart';

/// Outcome of exporting one [DataSource].
enum SourceExportStatus {
  /// The data was exported.
  success,

  /// The source threw an error.
  failed,

  /// The source did not finish within the timeout.
  timedOut,

  /// The source returned data that cannot be encoded as JSON.
  notSerializable,
}

/// Result for one [DataSource].
final class SourceExportResult {
  /// Creates a result.
  const SourceExportResult({
    required this.sourceId,
    required this.status,
    this.data,
    this.error,
    this.stackTrace,
  });

  /// The source id.
  final String sourceId;

  /// What happened.
  final SourceExportStatus status;

  /// The exported data, if [status] is [SourceExportStatus.success].
  final Object? data;

  /// The error, for the app to log or show. Not written to the export file.
  final Object? error;

  /// The stack trace of [error], if any.
  final StackTrace? stackTrace;

  /// Whether the source was exported.
  bool get isSuccess => status == SourceExportStatus.success;
}

/// Progress of a running export.
final class ExportProgress {
  /// Creates a progress update.
  const ExportProgress({
    required this.completed,
    required this.total,
    required this.sourceId,
    required this.status,
  });

  /// Number of sources finished so far.
  final int completed;

  /// Number of registered sources.
  final int total;

  /// The source that just finished.
  final String sourceId;

  /// How it finished.
  final SourceExportStatus status;

  /// [completed] divided by [total], from 0 to 1.
  double get fraction => total == 0 ? 1 : completed / total;
}

/// A finished export. Encode it with [toJsonString] and give the file to the
/// user, for example through a share sheet.
final class DataExport {
  /// Creates an export. Intended for [DataExporter] and tests.
  DataExport({
    required this.appId,
    required DateTime exportedAt,
    required List<SourceExportResult> results,
  }) : exportedAt = exportedAt.toUtc(),
       results = List.unmodifiable(results);

  /// Version of the JSON layout produced by [toJson].
  static const int schemaVersion = 1;

  /// The app identifier passed to [DataExporter].
  final String appId;

  /// When the export was created, in UTC.
  final DateTime exportedAt;

  /// One result per source, in registration order.
  final List<SourceExportResult> results;

  /// Whether every source was exported.
  bool get isComplete => results.every((r) => r.isSuccess);

  /// Sources that were not exported.
  List<SourceExportResult> get failures => [
    for (final r in results)
      if (!r.isSuccess) r,
  ];

  /// A file name such as `com.example.app-data-export-20261018T120000Z.json`.
  String get suggestedFileName {
    final stamp = exportedAt
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .replaceAll(RegExp(r'\.\d+'), '');
    final safeApp = appId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '$safeApp-data-export-$stamp.json';
  }

  /// The export document.
  ///
  /// Failed sources are listed with their status and no data, so the user
  /// can see what is missing. Error details are not included.
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'app_id': appId,
    'export_date': exportedAt.toIso8601String(),
    'complete': isComplete,
    'sources': [for (final r in results) r.sourceId],
    'data': {
      for (final r in results)
        r.sourceId: {
          'status': _statusName(r.status),
          if (r.isSuccess) 'data': r.data,
        },
    },
  };

  /// [toJson] encoded as a string, indented when [pretty] is `true`.
  String toJsonString({bool pretty = true}) => pretty
      ? const JsonEncoder.withIndent('  ').convert(toJson())
      : jsonEncode(toJson());

  static String _statusName(SourceExportStatus status) => switch (status) {
    SourceExportStatus.success => 'ok',
    SourceExportStatus.failed => 'failed',
    SourceExportStatus.timedOut => 'timed_out',
    SourceExportStatus.notSerializable => 'not_serializable',
  };
}

/// Collects the user's data from every registered [DataSource] into one
/// JSON document ("export my data", GDPR Art. 15 and 20).
///
/// One failing source does not stop the export. Its status is reported in
/// [DataExport.results] and in the document, so nothing fails silently.
final class DataExporter {
  /// Creates an exporter.
  ///
  /// [appId] identifies the app in the export, for example the bundle id.
  /// [sourceTimeout] limits how long one source may take.
  DataExporter({
    required this.appId,
    this.auditTrail,
    this.sourceTimeout = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static final RegExp _idPattern = RegExp(r'^[a-z][a-z0-9_.\-]*$');

  /// App identifier written to the export.
  final String appId;

  /// Optional audit trail for `data_exported` events.
  final AuditTrail? auditTrail;

  /// Maximum time per source.
  final Duration sourceTimeout;

  final DateTime Function() _clock;
  final List<DataSource> _sources = [];

  /// Ids of registered sources, in registration order.
  List<String> get sourceIds => [for (final s in _sources) s.id];

  /// Registers [source].
  ///
  /// Throws [InvalidConfigurationException] if the id is invalid
  /// (`[a-z][a-z0-9_.-]*`, at most 64 characters) or already registered.
  void register(DataSource source) {
    final id = source.id;
    if (!_idPattern.hasMatch(id) || id.length > 64) {
      throw InvalidConfigurationException(
        'Data source id "$id" must match [a-z][a-z0-9_.-]* and be at most '
        '64 characters.',
      );
    }
    if (_sources.any((s) => s.id == id)) {
      throw InvalidConfigurationException(
        'Data source "$id" is already registered.',
      );
    }
    _sources.add(source);
  }

  /// Removes the source with [id]. Returns whether it was registered.
  bool unregister(String id) {
    final before = _sources.length;
    _sources.removeWhere((s) => s.id == id);
    return _sources.length != before;
  }

  /// Exports every registered source, one after another, reporting
  /// [onProgress] after each.
  Future<DataExport> export({
    void Function(ExportProgress progress)? onProgress,
  }) async {
    final sources = List.of(_sources);
    final results = <SourceExportResult>[];
    for (final source in sources) {
      final result = await _exportOne(source);
      results.add(result);
      onProgress?.call(
        ExportProgress(
          completed: results.length,
          total: sources.length,
          sourceId: source.id,
          status: result.status,
        ),
      );
    }
    final export = DataExport(
      appId: appId,
      exportedAt: _clock(),
      results: results,
    );
    await _audit(export);
    return export;
  }

  Future<SourceExportResult> _exportOne(DataSource source) async {
    final Object? data;
    try {
      data = await source.export().timeout(sourceTimeout);
    } on TimeoutException catch (e, st) {
      return SourceExportResult(
        sourceId: source.id,
        status: SourceExportStatus.timedOut,
        error: e,
        stackTrace: st,
      );
    } on Object catch (e, st) {
      return SourceExportResult(
        sourceId: source.id,
        status: SourceExportStatus.failed,
        error: e,
        stackTrace: st,
      );
    }
    try {
      // Round-trip to get a detached, JSON-only copy.
      return SourceExportResult(
        sourceId: source.id,
        status: SourceExportStatus.success,
        data: jsonDecode(jsonEncode(data)),
      );
    } on Object catch (e, st) {
      return SourceExportResult(
        sourceId: source.id,
        status: SourceExportStatus.notSerializable,
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _audit(DataExport export) async {
    final trail = auditTrail;
    if (trail == null) return;
    try {
      await trail.record(
        AuditEvent(
          type: GdprAuditEvents.dataExported,
          source: GdprAuditEvents.source,
          timestamp: export.exportedAt,
          metadata: {
            'sources': export.results.length,
            'failed': export.failures.length,
            'complete': export.isComplete,
          },
        ),
      );
    } on Object {
      // A failing audit trail must not break the export.
    }
  }
}
