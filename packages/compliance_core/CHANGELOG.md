## 0.1.0

- Initial release.
- `AuditEvent` with UTC timestamps, identifier validation and primitive-only metadata.
- `AuditTrail` interface, `InMemoryAuditTrail` (optional size cap) and `NoopAuditTrail`.
- `ComplianceException` base type with `InvalidAuditEventException`, `InvalidConfigurationException` and `ComplianceStateException`.
