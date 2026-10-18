import 'consent_record.dart';

/// Persists consent records.
///
/// Implement this with your app's storage (for example a database table or
/// a preferences file). The store must keep records in the order they were
/// appended. Consent records are personal data: store them on the device
/// with the same protection as other user data and include them in data
/// export and deletion.
abstract interface class ConsentStore {
  /// Returns all stored records, oldest first.
  Future<List<ConsentRecord>> load();

  /// Appends [records] after the existing ones.
  Future<void> append(List<ConsentRecord> records);

  /// Removes all records.
  Future<void> clear();
}

/// A [ConsentStore] that keeps records in memory. Records are lost when the
/// app restarts, so use it only for tests, examples and prototypes.
final class InMemoryConsentStore implements ConsentStore {
  /// Creates a store, optionally pre-filled with [initial] records.
  InMemoryConsentStore([List<ConsentRecord> initial = const []])
    : _records = List.of(initial);

  final List<ConsentRecord> _records;

  @override
  Future<List<ConsentRecord>> load() async => List.unmodifiable(_records);

  @override
  Future<void> append(List<ConsentRecord> records) async =>
      _records.addAll(records);

  @override
  Future<void> clear() async => _records.clear();
}
