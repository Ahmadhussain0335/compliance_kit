## 0.1.0

Initial release.

- `ConsentManager`: purposes defined by the app, nothing optional enabled by default, strictly necessary purposes always active, policy versioning (consent from an older version does not count), append-only history, `changes` stream and `watch(purposeId)`, one-call `withdraw`, `reset()` for account deletion.
- `ConsentStore` interface with `InMemoryConsentStore`; stored records are validated on load.
- Consent UI: `showConsentDialog`, `showConsentBottomSheet`, `ConsentPrompt`, `PrivacySettingsScreen`, `ConsentChoiceButtons`, `ConsentStrings`. Accept and reject use the same widget, style, width and height; one-toggle withdrawal; no dismissal without a choice; save errors shown to the user; screen reader and large-text support; all strings overridable.
- `DataExporter` with `DataSource`, `CallbackDataSource` and `RedactingDataSource`: one JSON document with metadata, progress reporting, per-source status (`ok`, `failed`, `timed_out`, `not_serializable`); incomplete redaction is reported as a failure (`IncompleteRedactionException`).
- `DataDeletionManager` with `DataEraser`: required confirmation step, server deletion callback that can report an already deleted account, per-step report (deleted, skipped, failed), local data kept when the server step fails (configurable), retry of failed steps, idempotent and safe against concurrent calls.
- Audit events, recorded in the background with `onAuditError` for failures: `consent_granted`, `consent_denied`, `consent_withdrawn`, `consent_policy_changed`, `data_exported`, `data_deletion_requested`, `data_deletion_completed`. No personal data in metadata.
