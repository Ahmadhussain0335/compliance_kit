# Changelog

Release notes for the Compliance Kit family. Each package also has its own `CHANGELOG.md`, which is what pub.dev shows.

## 0.1.0-beta.1 - 2026-10-19

First beta release of all packages. APIs may change before 1.0.0. Integrity flows are not yet verified on physical devices.

| Package | Highlights |
|---|---|
| [compliance_core](packages/compliance_core/CHANGELOG.md) | `AuditEvent`, `AuditTrail` (in-memory, no-op), `ComplianceException` hierarchy |
| [compliance_logger](packages/compliance_logger/CHANGELOG.md) | PII-redacting logger, built-in and custom rules, keyed hash masking, fail-closed redaction |
| [compliance_gdpr](packages/compliance_gdpr/CHANGELOG.md) | Consent with policy versions, accessible consent UI, data export, account deletion |
| [compliance_integrity](packages/compliance_integrity/CHANGELOG.md) | Play Integrity (Android) and App Attest (iOS), typed results, no Firebase |
| [compliance_kit](packages/compliance_kit/CHANGELOG.md) | Umbrella package and `ComplianceKit.init` |

Also in this release (not published to pub.dev):

- `server/`: reference verification server for Play Integrity and App Attest, with Apple's sample attestation as a test vector.
- `docs/`: guides per package and an audit trail guide.
- CI: format, analysis, tests with a 90% coverage gate for pure Dart packages, Android plugin unit tests and an iOS simulator build.
