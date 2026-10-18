## 0.1.0

- Initial release.
- Re-exports compliance_core, compliance_logger, compliance_gdpr and compliance_integrity.
- `ComplianceKit.init` wires the logger, consent, export, deletion and integrity modules to one shared audit trail.
- Consent-gated log forwarding (`forwardLogs` + `forwardLogsPurpose`).
- Consent history registered as an export source by default; optional erasure on account deletion.
