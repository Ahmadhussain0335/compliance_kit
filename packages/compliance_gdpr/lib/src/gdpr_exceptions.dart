import 'package:compliance_core/compliance_core.dart';

/// Thrown when a consent operation is invalid, for example withdrawing a
/// strictly necessary purpose or using an unknown purpose id.
class ConsentException extends ComplianceException {
  /// Creates a [ConsentException].
  const ConsentException(super.message, {super.cause});

  @override
  String get code => 'invalid_consent_operation';
}

/// Thrown by `RedactingDataSource` when redaction could not process the
/// whole source (a rule failed, or a size or depth limit was reached), so
/// the export is not silently incomplete.
class IncompleteRedactionException extends ComplianceException {
  /// Creates the exception.
  const IncompleteRedactionException(super.message, {super.cause});

  @override
  String get code => 'incomplete_redaction';
}
