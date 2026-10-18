/// GDPR building blocks for Flutter apps: consent management with policy
/// versioning, data export, account deletion, and an accessible consent UI.
///
/// Every flow can record audit events through a `compliance_core`
/// `AuditTrail`. Event metadata never contains personal data.
library;

export 'src/consent/consent_manager.dart';
export 'src/consent/consent_policy.dart';
export 'src/consent/consent_record.dart';
export 'src/consent/consent_state.dart';
export 'src/consent/consent_store.dart';
export 'src/deletion/data_deletion_manager.dart';
export 'src/deletion/data_eraser.dart';
export 'src/export/data_exporter.dart';
export 'src/export/data_source.dart';
export 'src/gdpr_audit_events.dart';
export 'src/gdpr_exceptions.dart';
export 'src/ui/consent_choice_buttons.dart';
export 'src/ui/consent_prompt.dart';
export 'src/ui/consent_strings.dart';
export 'src/ui/privacy_settings_screen.dart';
