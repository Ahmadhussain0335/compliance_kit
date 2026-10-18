import 'dart:convert';

import 'log_record.dart';

/// Destination for redacted [LogRecord]s.
///
/// Sinks only ever receive records that have been through the redactor.
/// Implement this to forward logs to a file, a crash reporter or a backend.
abstract class LogSink {
  /// Const constructor for subclasses.
  const LogSink();

  /// Handles one record. Must not throw for normal records; the logger
  /// catches errors from sinks so that logging never breaks the app.
  void write(LogRecord record);

  /// Releases resources. The default does nothing.
  Future<void> close() async {}
}

/// Formats a [LogRecord] as text.
typedef LogFormatter = String Function(LogRecord record);

/// Writes records as text lines.
///
/// By default lines go to `print`, which works on every platform including
/// the web. Pass a `writer` to send them elsewhere, for example to
/// `stderr.writeln` on the server.
final class ConsoleSink extends LogSink {
  /// Creates a console sink.
  const ConsoleSink({void Function(String line)? writer, this.formatter})
    : _writer = writer;

  final void Function(String line)? _writer;

  /// Custom formatter. If `null`, [defaultFormat] is used.
  final LogFormatter? formatter;

  @override
  void write(LogRecord record) {
    final line = (formatter ?? defaultFormat)(record);
    final writer = _writer;
    if (writer != null) {
      writer(line);
    } else {
      // ignore: avoid_print
      print(line);
    }
  }

  /// Formats as `<ISO time> [LEVEL] name: message {fields}` followed by the
  /// error and stack trace on separate lines.
  static String defaultFormat(LogRecord record) {
    final buffer = StringBuffer()
      ..write(record.time.toIso8601String())
      ..write(' [')
      ..write(record.level.label)
      ..write('] ')
      ..write(record.loggerName)
      ..write(': ')
      ..write(record.message);
    final fields = record.fields;
    if (fields != null && fields.isNotEmpty) {
      buffer
        ..write(' ')
        ..write(jsonEncode(fields));
    }
    if (record.error != null) {
      buffer
        ..write('\n  error: ')
        ..write(record.error);
    }
    if (record.stackTrace != null) {
      buffer
        ..write('\n')
        ..write(record.stackTrace);
    }
    return buffer.toString();
  }
}

/// Keeps records in memory. Intended for tests.
final class MemorySink extends LogSink {
  /// Creates a memory sink. If [maxRecords] is set, the oldest records are
  /// dropped once the limit is reached.
  MemorySink({this.maxRecords});

  /// Maximum number of records kept, or `null` for no limit.
  final int? maxRecords;

  final List<LogRecord> _records = [];

  /// Records received so far, oldest first. Unmodifiable snapshot.
  List<LogRecord> get records => List.unmodifiable(_records);

  /// Messages of [records], oldest first.
  List<String> get messages => [for (final r in _records) r.message];

  @override
  void write(LogRecord record) {
    _records.add(record);
    final max = maxRecords;
    if (max != null && _records.length > max) {
      _records.removeRange(0, _records.length - max);
    }
  }

  /// Removes all records.
  void clear() => _records.clear();
}

/// Passes each record to a callback.
///
/// Use it to forward redacted logs to services such as Crashlytics or
/// Sentry without this package depending on them:
///
/// ```dart
/// CallbackSink((record) {
///   if (record.level.isAtLeast(LogLevel.error)) {
///     crashReporter.log(record.message);
///   }
/// });
/// ```
final class CallbackSink extends LogSink {
  /// Creates a callback sink. [onClose] runs when the sink is closed.
  const CallbackSink(this.onRecord, {this.onClose});

  /// Called for every record.
  final void Function(LogRecord record) onRecord;

  /// Called by [close], if given.
  final Future<void> Function()? onClose;

  @override
  void write(LogRecord record) => onRecord(record);

  @override
  Future<void> close() async {
    await onClose?.call();
  }
}
