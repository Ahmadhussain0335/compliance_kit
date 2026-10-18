/// Outcome of deleting one data location.
enum ErasureStatus {
  /// The data was deleted.
  deleted,

  /// Nothing was done, for example because there was no data or an earlier
  /// step failed. See `SourceDeletionResult.reason`.
  skipped,

  /// Deletion failed. The step can be retried.
  failed,
}

/// Deletes the user's data from one local location, for example a database,
/// preferences, files or caches.
///
/// [erase] must be idempotent: running it again after a successful or
/// partial run must not fail just because the data is already gone.
abstract class DataEraser {
  /// Const constructor for subclasses.
  const DataEraser();

  /// Stable identifier, for example `orders_db`. Must not contain personal
  /// data.
  String get id;

  /// Deletes the data. Returns [ErasureStatus.deleted] or
  /// [ErasureStatus.skipped]; throw to report a failure.
  Future<ErasureStatus> erase();
}

/// A [DataEraser] backed by a function.
final class CallbackDataEraser extends DataEraser {
  /// Creates an eraser that calls [eraser].
  const CallbackDataEraser(this.id, this.eraser);

  @override
  final String id;

  /// Performs the deletion.
  final Future<ErasureStatus> Function() eraser;

  @override
  Future<ErasureStatus> erase() => eraser();
}
