import 'package:compliance_logger/compliance_logger.dart';

/// A place where the app stores the user's data, for example a database
/// table, preferences or files.
///
/// Register one source per place with a `DataExporter`. [export] must
/// return JSON-encodable data: `null`, `bool`, `num`, `String`, and `List`
/// or `Map<String, ...>` of those.
abstract class DataSource {
  /// Const constructor for subclasses.
  const DataSource();

  /// Stable identifier, for example `orders_db`. Appears in the export file
  /// and in audit events, so it must not contain personal data.
  String get id;

  /// Returns this source's data for the current user.
  Future<Object?> export();
}

/// A [DataSource] backed by a function.
final class CallbackDataSource extends DataSource {
  /// Creates a source that calls [exporter].
  const CallbackDataSource(this.id, this.exporter);

  @override
  final String id;

  /// Returns the data.
  final Future<Object?> Function() exporter;

  @override
  Future<Object?> export() => exporter();
}

/// Wraps a [DataSource] and redacts its output with a [Redactor].
///
/// Use it for sources such as logs or support transcripts that may contain
/// personal data about other people, which should not be handed to the
/// requesting user. Redaction is pattern-based and cannot find every kind
/// of personal data; review what such sources contain.
final class RedactingDataSource extends DataSource {
  /// Creates a redacting wrapper around [inner].
  const RedactingDataSource(this.inner, this.redactor);

  /// The wrapped source.
  final DataSource inner;

  /// The redactor applied to the exported data.
  final Redactor redactor;

  @override
  String get id => inner.id;

  @override
  Future<Object?> export() async => redactor.redactValue(await inner.export());
}
