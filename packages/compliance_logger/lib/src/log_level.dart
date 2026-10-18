/// Severity of a log record, from least to most severe.
enum LogLevel implements Comparable<LogLevel> {
  /// Very detailed tracing, usually only enabled while debugging.
  trace,

  /// Diagnostic information for developers.
  debug,

  /// Normal operational messages.
  info,

  /// Something unexpected that the app recovered from.
  warning,

  /// An operation failed.
  error,

  /// A failure the app cannot recover from.
  fatal;

  /// Upper-case label used by the console sink, for example `INFO`.
  String get label => name.toUpperCase();

  /// Whether this level is at least as severe as [other].
  bool isAtLeast(LogLevel other) => index >= other.index;

  @override
  int compareTo(LogLevel other) => index.compareTo(other.index);
}
