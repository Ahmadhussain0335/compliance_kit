/// Base type for every exception thrown by Compliance Kit packages.
///
/// Catch this type to handle any Compliance Kit failure in one place. The
/// [message] is written for developers and never contains personal data.
/// The optional [cause] is the underlying error, if any; it is not included
/// in [toString] because it may carry data the library does not control.
abstract class ComplianceException implements Exception {
  /// Creates an exception with a developer-facing [message] and an optional
  /// underlying [cause].
  const ComplianceException(this.message, {this.cause});

  /// Developer-facing description of the failure. Never contains personal
  /// data.
  final String message;

  /// The underlying error that triggered this exception, if any.
  final Object? cause;

  /// Stable, machine-readable error code, for example `invalid_audit_event`.
  String get code;

  @override
  String toString() => 'ComplianceException[$code]: $message';
}

/// Thrown when an `AuditEvent` is constructed or decoded with invalid data,
/// for example an empty type or a metadata value that is not a primitive.
class InvalidAuditEventException extends ComplianceException {
  /// Creates an [InvalidAuditEventException].
  const InvalidAuditEventException(super.message, {super.cause});

  @override
  String get code => 'invalid_audit_event';
}

/// Thrown when a Compliance Kit component is configured with invalid values.
class InvalidConfigurationException extends ComplianceException {
  /// Creates an [InvalidConfigurationException].
  const InvalidConfigurationException(super.message, {super.cause});

  @override
  String get code => 'invalid_configuration';
}

/// Thrown when an operation is called in a state that does not allow it,
/// for example recording an event after the audit trail was disposed.
class ComplianceStateException extends ComplianceException {
  /// Creates a [ComplianceStateException].
  const ComplianceStateException(super.message, {super.cause});

  @override
  String get code => 'invalid_state';
}
