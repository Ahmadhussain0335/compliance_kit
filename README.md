# Compliance Kit

Open-source Dart and Flutter packages that help apps implement privacy and security controls: PII-safe logging, GDPR consent, data export and deletion, and app integrity checks, all recording into one audit trail.

[![CI](https://github.com/Ahmadhussain0335/compliance_kit/actions/workflows/ci.yaml/badge.svg)](https://github.com/Ahmadhussain0335/compliance_kit/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![pub version](https://img.shields.io/pub/v/compliance_kit?include_prereleases)](https://pub.dev/packages/compliance_kit) [![pub points](https://img.shields.io/pub/points/compliance_kit)](https://pub.dev/packages/compliance_kit/score) [![pub likes](https://img.shields.io/pub/likes/compliance_kit)](https://pub.dev/packages/compliance_kit/score)

> **Beta: 0.1.0-beta.1.** APIs may change before 1.0.0. Feedback welcome via [GitHub issues](https://github.com/Ahmadhussain0335/compliance_kit/issues). See the [changelog](CHANGELOG.md).

> **Note:** Not yet verified on physical devices. Play Integrity and App Attest flows are covered by unit tests with mocked platform interfaces only. Please report device results in [GitHub issues](https://github.com/Ahmadhussain0335/compliance_kit/issues).

Built for apps that have to meet GDPR, the EU Cyber Resilience Act, EN 18031 / RED delegated act and OWASP MASVS requirements. The packages implement concrete controls (redacted logs, recorded consent, export, deletion, attestation) and record evidence in one audit trail.

## Which package do I need?

| Package | Platform | Use it when you need |
|---|---|---|
| [`compliance_kit`](packages/compliance_kit) | Flutter | Everything below with one dependency and `ComplianceKit.init`. |
| [`compliance_logger`](packages/compliance_logger) | Pure Dart (Flutter, server, web) | Logs and crash reports that never contain emails, phone numbers, tokens, API keys, card numbers or IBANs. |
| [`compliance_gdpr`](packages/compliance_gdpr) | Flutter | Granular consent with policy versioning and an accessible UI; "export my data"; "delete my account". |
| [`compliance_integrity`](packages/compliance_integrity) | Flutter plugin (Android, iOS) | Proof that requests come from your genuine app on a genuine device: Play Integrity and App Attest, no Firebase. |
| [`compliance_core`](packages/compliance_core) | Pure Dart | The shared audit trail and exceptions. Pulled in by the others. |
| [`server/`](server) | Dart (not published) | Reference server that verifies integrity tokens. |

## Quick start

### Everything

```dart
final kit = await ComplianceKit.init(appId: 'com.example.app', consentPolicy: policy);
kit.logger.info('Signed in as jane.doe@example.com'); // ... [REDACTED:email]
```

### Logger only

```dart
final log = ComplianceLogger(name: 'app');
log.warning('Payment failed', fields: {'card': '4111 1111 1111 1111'}); // {"card":"[REDACTED:credit_card]"}
```

### Consent, export, deletion

```dart
final consent = ConsentManager(policy: policy, store: myStore);
await consent.initialize();
if (consent.state.needsConsent) await showConsentDialog(context, manager: consent);
consent.watch('analytics').listen(analytics.setEnabled);

final exporter = DataExporter(appId: 'com.example.app')
  ..register(CallbackDataSource('profile', () async => profileDao.toJson()));
final export = await exporter.export();
```

### Integrity

```dart
final integrity = Integrity(cloudProjectNumber: 123456789012);
final challenge = await api.challenge();
if (await integrity.requestToken(challenge) case IntegritySuccess(:final token, :final kind)) {
  await api.verify(token, kind, challenge); // your server decides
}
```

## Install

```sh
flutter pub add compliance_kit:^0.1.0-beta.1          # everything
dart pub add compliance_logger:^0.1.0-beta.1          # logger only (also for Dart servers)
flutter pub add compliance_gdpr:^0.1.0-beta.1         # consent, export, deletion
flutter pub add compliance_integrity:^0.1.0-beta.1    # Play Integrity + App Attest
```

## Platform support

| Package | Android | iOS | Web | macOS | Windows | Linux | Dart server |
|---|---|---|---|---|---|---|---|
| compliance_core | yes | yes | yes | yes | yes | yes | yes |
| compliance_logger | yes | yes | yes | yes | yes | yes | yes |
| compliance_gdpr | yes | yes | yes | yes | yes | yes | no |
| compliance_integrity | yes | yes | no | no | no | no | no |
| compliance_kit | yes | yes | no | no | no | no | no |

`compliance_integrity` (and therefore `compliance_kit`) contains native code for Android and iOS only. On other platforms `Integrity` returns `IntegrityUnsupported` instead of throwing.

## Roadmap to 1.0.0

1. **Real-device verification** of Play Integrity and App Attest (the checklist in the [compliance_integrity README](packages/compliance_integrity/README.md#manual-real-device-test-checklist)), and testing on the minimum supported Flutter version.
2. **Community feedback** on the APIs and defaults during the beta, through [GitHub issues](https://github.com/Ahmadhussain0335/compliance_kit/issues).
3. **API freeze**: review the public APIs, resolve breaking changes, then release 1.0.0 with semantic versioning guarantees.

## Guides

See [docs/](docs): getting started, one guide per package, and [how to use the audit trail with auditors](docs/audit-trail.md).

## Repository layout

```
packages/
  compliance_core/        audit trail and exceptions (pure Dart)
  compliance_logger/      PII-redacting logger (pure Dart)
  compliance_gdpr/        consent, export, deletion, consent UI (Flutter)
  compliance_integrity/   Play Integrity + App Attest plugin (Flutter, Kotlin, Swift)
  compliance_kit/         umbrella package and ComplianceKit.init
server/                   reference verification server (Dart, not published)
docs/                     guides
```

Every Flutter package has a runnable `example/` app.

## Security

Please report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Release steps are in [RELEASE.md](RELEASE.md).

## Development

A [Dart pub workspace](https://dart.dev/tools/pub/workspaces) managed with [melos](https://melos.invertase.dev) 8.

```sh
flutter pub get                                  # resolve the whole workspace
dart run melos run analyze --no-select
dart run melos run format
dart run melos run test --no-select
dart run melos run coverage --no-select          # pure Dart packages, 90% line coverage gate
dart run melos run publish-dry-run --no-select
```

Requirements: Flutter 3.47.7 stable (Dart 3.13.5) for development. Packages declare `sdk: ^3.9.0` and `flutter: >=3.35.0`.

## Disclaimer

Compliance Kit helps developers implement privacy and security controls. It does not by itself make an application compliant with GDPR, the CRA, EN 18031, OWASP MASVS or any other regulation or standard. Compliance depends on the whole system and must be assessed separately.

## License

MIT. See [LICENSE](LICENSE).
