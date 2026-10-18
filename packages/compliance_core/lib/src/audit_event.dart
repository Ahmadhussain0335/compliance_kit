import 'exceptions.dart';

/// A single entry in an audit trail.
///
/// An audit event records that something compliance-relevant happened, for
/// example that consent was granted or that a log message was redacted. It
/// describes *what* happened, never *to whom*:
///
/// * [type] and [source] are short identifiers such as `consent_granted` and
///   `compliance_gdpr`.
/// * [metadata] holds flat, primitive values only (`String`, `int`, `double`,
///   `bool` or `null`). Nested maps, lists and objects are rejected so that
///   whole objects cannot be dumped into the trail by accident.
///
/// The library cannot detect every kind of personal data, so callers are
/// responsible for never putting raw personal data (emails, names, device
/// identifiers, tokens) into [metadata]. Use counts, categories and result
/// codes instead.
///
/// [timestamp] is always stored in UTC.
final class AuditEvent {
  /// Creates an audit event.
  ///
  /// If [timestamp] is omitted, the current time is used. A non-UTC
  /// [timestamp] is converted to UTC.
  ///
  /// Throws [InvalidAuditEventException] if [type] or [source] is not a valid
  /// identifier (lowercase letters, digits, `_`, `.`, `-`; starting with a
  /// letter; at most [maxIdentifierLength] characters), or if [metadata]
  /// breaks the rules described on the class.
  AuditEvent({
    required this.type,
    required this.source,
    DateTime? timestamp,
    Map<String, Object?> metadata = const {},
  }) : timestamp = (timestamp ?? DateTime.now()).toUtc(),
       metadata = Map.unmodifiable(_validateMetadata(metadata)) {
    _validateIdentifier('type', type);
    _validateIdentifier('source', source);
  }

  /// Decodes an event produced by [toJson].
  ///
  /// Throws [InvalidAuditEventException] if [json] is malformed.
  factory AuditEvent.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    final source = json['source'];
    final timestamp = json['timestamp'];
    final metadata = json['metadata'] ?? const <String, Object?>{};
    if (type is! String || source is! String || timestamp is! String) {
      throw const InvalidAuditEventException(
        'type, source and timestamp must be strings.',
      );
    }
    if (metadata is! Map) {
      throw const InvalidAuditEventException('metadata must be a map.');
    }
    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) {
      throw const InvalidAuditEventException(
        'timestamp is not an ISO-8601 date.',
      );
    }
    final typedMetadata = <String, Object?>{};
    for (final entry in metadata.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const InvalidAuditEventException(
          'metadata keys must be strings.',
        );
      }
      typedMetadata[key] = entry.value;
    }
    return AuditEvent(
      type: type,
      source: source,
      timestamp: parsed,
      metadata: typedMetadata,
    );
  }

  /// Maximum length of [type], [source] and metadata keys.
  static const int maxIdentifierLength = 64;

  /// Maximum number of entries in [metadata].
  static const int maxMetadataEntries = 32;

  /// Maximum length of a string value in [metadata].
  ///
  /// The limit keeps metadata to short codes and labels and makes it harder
  /// to store free text, which is where personal data tends to leak in.
  static const int maxMetadataValueLength = 256;

  static final RegExp _identifierPattern = RegExp(r'^[a-z][a-z0-9_.\-]*$');
  static final RegExp _metadataKeyPattern = RegExp(
    r'^[A-Za-z][A-Za-z0-9_.\-]*$',
  );

  /// What happened, for example `consent_granted`.
  final String type;

  /// When it happened, in UTC.
  final DateTime timestamp;

  /// The package or component that recorded the event, for example
  /// `compliance_logger`.
  final String source;

  /// Additional primitive, non-personal details. Unmodifiable.
  final Map<String, Object?> metadata;

  /// Encodes this event as a JSON-compatible map.
  ///
  /// The timestamp is written as an ISO-8601 UTC string.
  Map<String, Object?> toJson() => {
    'type': type,
    'timestamp': timestamp.toIso8601String(),
    'source': source,
    'metadata': Map<String, Object?>.of(metadata),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AuditEvent ||
        other.type != type ||
        other.source != source ||
        other.timestamp != timestamp ||
        other.metadata.length != metadata.length) {
      return false;
    }
    for (final entry in metadata.entries) {
      if (!other.metadata.containsKey(entry.key) ||
          other.metadata[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    type,
    source,
    timestamp,
    Object.hashAllUnordered(
      metadata.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'AuditEvent(type: $type, source: $source, '
      'timestamp: ${timestamp.toIso8601String()}, metadata: $metadata)';

  static void _validateIdentifier(String field, String value) {
    if (value.isEmpty ||
        value.length > maxIdentifierLength ||
        !_identifierPattern.hasMatch(value)) {
      throw InvalidAuditEventException(
        '$field must be 1-$maxIdentifierLength characters of lowercase '
        'letters, digits, "_", "." or "-", starting with a letter.',
      );
    }
  }

  static Map<String, Object?> _validateMetadata(Map<String, Object?> metadata) {
    if (metadata.length > maxMetadataEntries) {
      throw const InvalidAuditEventException(
        'metadata must not have more than $maxMetadataEntries entries.',
      );
    }
    for (final entry in metadata.entries) {
      final key = entry.key;
      if (key.isEmpty ||
          key.length > maxIdentifierLength ||
          !_metadataKeyPattern.hasMatch(key)) {
        throw const InvalidAuditEventException(
          'metadata keys must be 1-$maxIdentifierLength characters of '
          'letters, digits, "_", "." or "-", starting with a letter.',
        );
      }
      final value = entry.value;
      switch (value) {
        case null || bool() || int():
          break;
        case double() when value.isFinite:
          break;
        case String() when value.length <= maxMetadataValueLength:
          break;
        case String():
          throw const InvalidAuditEventException(
            'metadata string values must not be longer than '
            '$maxMetadataValueLength characters.',
          );
        default:
          // The value itself is deliberately not included in the message.
          throw InvalidAuditEventException(
            'metadata value for "$key" must be a String, int, finite double, '
            'bool or null.',
          );
      }
    }
    return metadata;
  }
}
