import 'package:compliance_core/compliance_core.dart';

import 'log_level.dart';
import 'log_record.dart';
import 'redaction/redactor.dart';
import 'sinks.dart';

/// Called when a sink throws. Receives the error and stack trace thrown by
/// the sink, never the log record.
typedef SinkErrorHandler = void Function(Object error, StackTrace stackTrace);

/// A logger that redacts personal data and secrets before any sink sees
/// them.
///
/// The message, the error's `toString()`, the stack trace text and every
/// structured field are passed through [redactor] first. Sinks only receive
/// the redacted [LogRecord].
///
/// ```dart
/// final log = ComplianceLogger(name: 'checkout');
/// log.info('Payment by jane.doe@example.com'); // Payment by [REDACTED:email]
/// ```
///
/// If [auditTrail] is set, a `log_redaction` event with per-rule counts is
/// recorded whenever a record had values masked. The masked values are never
/// part of the event.
final class ComplianceLogger {
  /// Creates a logger.
  ///
  /// * [minLevel]: records below this level are dropped before redaction.
  /// * [sinks]: destinations, a [ConsoleSink] if omitted.
  /// * [redactor]: a `Redactor` with the built-in rules if omitted.
  /// * [auditTrail]: optional trail for `log_redaction` events.
  /// * [onSinkError]: called when a sink throws. Errors are otherwise
  ///   ignored so that logging never breaks the app.
  /// * [clock]: time source, for tests.
  ComplianceLogger({
    this.name = 'app',
    this.minLevel = LogLevel.info,
    List<LogSink>? sinks,
    Redactor? redactor,
    this.auditTrail,
    this.onSinkError,
    DateTime Function()? clock,
  }) : sinks = List.unmodifiable(sinks ?? const [ConsoleSink()]),
       redactor = redactor ?? Redactor(),
       _clock = clock ?? DateTime.now;

  /// Audit event type for records with masked values.
  static const String redactionEventType = 'log_redaction';

  /// Audit event type for records where a redaction rule failed.
  static const String redactionFailedEventType = 'log_redaction_failed';

  /// Audit source used by this package.
  static const String auditSource = 'compliance_logger';

  /// Logger name, included in every record. Must not contain personal data.
  final String name;

  /// Minimum level that is logged.
  final LogLevel minLevel;

  /// Destinations for redacted records.
  final List<LogSink> sinks;

  /// The redactor applied to every record.
  final Redactor redactor;

  /// Optional audit trail for redaction events.
  final AuditTrail? auditTrail;

  /// Called when a sink throws.
  final SinkErrorHandler? onSinkError;

  final DateTime Function() _clock;

  /// Returns a logger with a different [name] that shares this logger's
  /// sinks, redactor, audit trail and level unless overridden.
  ComplianceLogger child(String name, {LogLevel? minLevel}) => ComplianceLogger(
    name: name,
    minLevel: minLevel ?? this.minLevel,
    sinks: sinks,
    redactor: redactor,
    auditTrail: auditTrail,
    onSinkError: onSinkError,
    clock: _clock,
  );

  /// Whether records at [level] are logged.
  bool isEnabled(LogLevel level) => level.isAtLeast(minLevel);

  /// Logs at [LogLevel.trace].
  void trace(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => log(
    LogLevel.trace,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  /// Logs at [LogLevel.debug].
  void debug(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => log(
    LogLevel.debug,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  /// Logs at [LogLevel.info].
  void info(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => log(
    LogLevel.info,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  /// Logs at [LogLevel.warning].
  void warning(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => log(
    LogLevel.warning,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  /// Logs at [LogLevel.error].
  void error(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => log(
    LogLevel.error,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  /// Logs at [LogLevel.fatal].
  void fatal(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) => log(
    LogLevel.fatal,
    message,
    error: error,
    stackTrace: stackTrace,
    fields: fields,
  );

  /// Redacts and writes a record at [level].
  ///
  /// [message] is converted with `toString()`; a `Function()` returning the
  /// message is called only if [level] is enabled, which avoids building
  /// expensive messages that would be dropped.
  void log(
    LogLevel level,
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? fields,
  }) {
    if (!isEnabled(level) || sinks.isEmpty) return;
    final counts = <String, int>{};
    final Map<String, Object?>? safeFields;
    if (fields == null) {
      safeFields = null;
    } else {
      final redacted = redactor.redactValue(fields, counts: counts);
      safeFields = redacted is Map<String, Object?>
          ? redacted
          : {'fields': redacted};
    }
    final record = LogRecord(
      level: level,
      loggerName: name,
      message: _safeText(
        () => message is Object? Function() ? message() : message,
        counts,
      ),
      time: _clock(),
      error: error == null ? null : _safeText(() => error, counts),
      stackTrace: stackTrace == null
          ? null
          : _safeText(() => stackTrace, counts),
      fields: safeFields,
      redactions: counts,
    );
    for (final sink in sinks) {
      try {
        // A sink declared `void` may still return a Future (for example an
        // async CallbackSink); route its errors to onSinkError as well.
        final result = (sink.write as Object? Function(LogRecord))(record);
        if (result is Future<Object?>) {
          result.then<void>((_) {}, onError: _reportSinkError).ignore();
        }
      } on Object catch (e, st) {
        _reportSinkError(e, st);
      }
    }
    _audit(level, counts);
  }

  /// Closes every sink. A sink that fails to close is reported to
  /// [onSinkError] and does not stop the others.
  Future<void> close() async {
    for (final sink in sinks) {
      try {
        await sink.close();
      } on Object catch (e, st) {
        _reportSinkError(e, st);
      }
    }
  }

  void _reportSinkError(Object error, StackTrace stackTrace) {
    try {
      onSinkError?.call(error, stackTrace);
    } on Object {
      // The error handler itself must not break logging.
    }
  }

  /// Produces text with [produce], redacts it, and fails closed: if
  /// producing the text or calling `toString()` throws, the result is
  /// `Redactor.failureMask`, because the exception may contain the raw text.
  String _safeText(Object? Function() produce, Map<String, int> counts) {
    final String raw;
    try {
      raw = produce().toString();
    } on Object {
      counts[Redactor.failureRuleId] =
          (counts[Redactor.failureRuleId] ?? 0) + 1;
      return Redactor.failureMask;
    }
    return _text(raw, counts);
  }

  String _text(String input, Map<String, int> counts) {
    final result = redactor.redact(input);
    result.counts.forEach((k, v) => counts[k] = (counts[k] ?? 0) + v);
    return result.text;
  }

  void _audit(LogLevel level, Map<String, int> counts) {
    final trail = auditTrail;
    if (trail == null || counts.isEmpty) return;
    final failed = counts.containsKey(Redactor.failureRuleId);
    final metadata = <String, Object?>{
      'level': level.name,
      'total': counts.values.fold<int>(0, (a, b) => a + b),
    };
    for (final entry in counts.entries) {
      if (metadata.length >= AuditEvent.maxMetadataEntries) break;
      metadata['rule.${entry.key}'] = entry.value;
    }
    try {
      trail
          .record(
            AuditEvent(
              type: failed ? redactionFailedEventType : redactionEventType,
              source: auditSource,
              timestamp: _clock(),
              metadata: metadata,
            ),
          )
          .ignore();
    } on Object {
      // Auditing must never break logging.
    }
  }
}
