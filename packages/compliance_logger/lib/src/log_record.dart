import 'log_level.dart';

/// A log entry after redaction. This is what sinks receive.
///
/// Every text field has already been redacted. The original error object
/// and stack trace are never passed on, only their redacted text, because
/// sinks may serialise them in ways the redactor cannot control.
final class LogRecord {
  /// Creates a record. Intended for `ComplianceLogger` and tests.
  LogRecord({
    required this.level,
    required this.loggerName,
    required this.message,
    required DateTime time,
    this.error,
    this.stackTrace,
    Map<String, Object?>? fields,
    Map<String, int> redactions = const {},
  }) : time = time.toUtc(),
       fields = fields == null ? null : Map.unmodifiable(fields),
       redactions = Map.unmodifiable(redactions);

  /// Severity.
  final LogLevel level;

  /// Name of the logger that produced the record.
  final String loggerName;

  /// Redacted message.
  final String message;

  /// When the record was created, in UTC.
  final DateTime time;

  /// Redacted `toString()` of the error, if one was logged.
  final String? error;

  /// Redacted stack trace text, if one was logged.
  final String? stackTrace;

  /// Redacted structured fields, if any. Unmodifiable.
  final Map<String, Object?>? fields;

  /// Number of values masked in this record, per rule id. Unmodifiable.
  final Map<String, int> redactions;

  /// Total number of values masked in this record.
  int get redactionCount => redactions.values.fold(0, (a, b) => a + b);
}
