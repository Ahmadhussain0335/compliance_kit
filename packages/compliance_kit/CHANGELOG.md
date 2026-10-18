## 0.1.0

Initial release.

- Re-exports `compliance_core`, `compliance_logger`, `compliance_gdpr` and `compliance_integrity`.
- `ComplianceKit.init` creates the logger, consent manager, data exporter, deletion manager and integrity client, all recording into one shared audit trail.
- Consent-gated log forwarding (`forwardLogs` + `forwardLogsPurpose`) for crash reporters.
- The user's consent history is registered as an export source by default; erasing it on account deletion is opt-in (`eraseConsentOnDeletion`).
- Example app using every module.
