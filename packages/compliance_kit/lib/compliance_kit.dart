/// Compliance Kit: privacy and security building blocks for Flutter.
///
/// Re-exports every package of the family and adds `ComplianceKit.init`,
/// which wires them to one shared audit trail:
///
/// * `compliance_core`: audit trail and exceptions;
/// * `compliance_logger`: PII-redacting logger;
/// * `compliance_gdpr`: consent, data export and account deletion;
/// * `compliance_integrity`: Play Integrity and App Attest.
library;

export 'package:compliance_core/compliance_core.dart';
export 'package:compliance_gdpr/compliance_gdpr.dart';
export 'package:compliance_integrity/compliance_integrity.dart';
export 'package:compliance_logger/compliance_logger.dart';

export 'src/compliance_kit.dart';
