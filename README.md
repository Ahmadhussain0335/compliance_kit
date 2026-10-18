# Compliance Kit

Open-source Dart and Flutter packages that help apps implement privacy and security controls: PII-safe logging, GDPR consent, data export and deletion, and app integrity checks.

[![CI](https://github.com/Ahmadhussain0335/compliance_kit/actions/workflows/ci.yaml/badge.svg)](https://github.com/Ahmadhussain0335/compliance_kit/actions/workflows/ci.yaml)

## Packages

| Package | Status | Platform | Use it when you need |
|---|---|---|---|
| [`compliance_core`](packages/compliance_core) | 0.1.0, ready for release | Pure Dart | An audit trail interface and shared exception types. Usually pulled in by the others. |
| [`compliance_logger`](packages/compliance_logger) | 0.1.0, ready for release | Pure Dart | Logging that masks emails, phone numbers, tokens, API keys, card numbers and IBANs before any sink sees them. |
| [`compliance_gdpr`](packages/compliance_gdpr) | Planned | Flutter | Granular consent with policy versioning, "export my data" and "delete my account" flows. |
| [`compliance_integrity`](packages/compliance_integrity) | Planned | Flutter plugin | Play Integrity (Android) and App Attest (iOS) without Firebase. |
| [`compliance_kit`](packages/compliance_kit) | Planned | Flutter | Everything above with one dependency and one setup call. |

All packages share one `AuditTrail` from `compliance_core`, so redactions, consent changes, exports, deletions and integrity checks can be recorded in one place and shown to auditors. Audit events never contain personal data.

## Quick start

```dart
import 'package:compliance_core/compliance_core.dart';
import 'package:compliance_logger/compliance_logger.dart';

final audit = InMemoryAuditTrail();
final log = ComplianceLogger(name: 'app', auditTrail: audit);

void main() {
  log.info('Password reset requested by jane.doe@example.com');
  // ... [INFO] app: Password reset requested by [REDACTED:email]
}
```

See each package README for details.

## Development

This repository is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces) managed with [melos](https://melos.invertase.dev) 8.

```sh
flutter pub get                               # resolve the whole workspace
dart run melos run analyze --no-select        # dart analyze --fatal-infos in every package
dart run melos run format                     # dart format .
dart run melos run test --no-select           # all tests
dart run melos run coverage --no-select       # pure Dart tests with a 90% line coverage gate
dart run melos run publish-dry-run --no-select
```

Requirements: Flutter 3.47.7 or newer stable (Dart 3.13.5). Packages declare `sdk: ^3.9.0`.

## Disclaimer

Compliance Kit helps developers implement privacy and security controls. It does not by itself make an application compliant with GDPR, the CRA, EN 18031, OWASP MASVS or any other regulation or standard. Compliance depends on the whole system and must be assessed separately.

## License

MIT. See [LICENSE](LICENSE).
