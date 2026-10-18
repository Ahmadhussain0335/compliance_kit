## 0.1.0-beta.1 - 2026-10-18

First beta release. APIs may change before 1.0.0.

- `AuditEvent` with UTC timestamps, identifier validation and primitive-only metadata.
- `AuditTrail` interface, `InMemoryAuditTrail` (optional size cap) and `NoopAuditTrail`.
- `ComplianceException` base type with `InvalidAuditEventException`, `InvalidConfigurationException` and `ComplianceStateException`.
