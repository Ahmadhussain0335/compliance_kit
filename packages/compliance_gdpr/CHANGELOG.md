## 0.1.0

- Initial release.
- `ConsentManager`: granular consent per purpose, nothing optional enabled by default, policy versioning, append-only history, change streams and `watch(purposeId)`.
- `ConsentStore` interface with `InMemoryConsentStore`.
- Consent UI: `showConsentDialog`, `showConsentBottomSheet`, `ConsentPrompt`, `PrivacySettingsScreen`, `ConsentChoiceButtons`. Equal-weight accept/reject, overridable strings, large-text and screen-reader support.
- `DataExporter` with `DataSource`, `CallbackDataSource` and `RedactingDataSource`; one JSON document with per-source status and progress reporting.
- `DataDeletionManager` with `DataEraser`, server deletion callback, confirmation step, per-step report, retry and concurrent-call protection.
- Audit events: `consent_granted`, `consent_denied`, `consent_withdrawn`, `consent_policy_changed`, `data_exported`, `data_deletion_requested`, `data_deletion_completed`.
