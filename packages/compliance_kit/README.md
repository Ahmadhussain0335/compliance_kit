# compliance_kit

[![pub version](https://img.shields.io/pub/v/compliance_kit?include_prereleases)](https://pub.dev/packages/compliance_kit) [![pub points](https://img.shields.io/pub/points/compliance_kit)](https://pub.dev/packages/compliance_kit/score) [![pub likes](https://img.shields.io/pub/likes/compliance_kit)](https://pub.dev/packages/compliance_kit/score)

> **Beta: 0.1.0-beta.1.** APIs may change before 1.0.0. Feedback welcome via [GitHub issues](https://github.com/Ahmadhussain0335/compliance_kit/issues).

Privacy and security toolkit for Flutter. One dependency for the whole Compliance Kit family:

| Module | What it does |
|---|---|
| [compliance_core](https://pub.dev/packages/compliance_core) | Shared audit trail and exception types |
| [compliance_logger](https://pub.dev/packages/compliance_logger) | Logger that masks emails, phone numbers, tokens, API keys, card numbers and IBANs before any sink sees them |
| [compliance_gdpr](https://pub.dev/packages/compliance_gdpr) | Granular consent with policy versions, "export my data", "delete my account", accessible consent UI |
| [compliance_integrity](https://pub.dev/packages/compliance_integrity) | Play Integrity (Android) and App Attest (iOS), no Firebase |

## Install

```sh
flutter pub add compliance_kit:^0.1.0-beta.1
```

or in `pubspec.yaml`:

```yaml
dependencies:
  compliance_kit: ^0.1.0-beta.1
```

## Quick start

```dart
import 'package:compliance_kit/compliance_kit.dart';

Future<void> main() async {
  final kit = await ComplianceKit.init(
    appId: 'com.example.app',
    consentPolicy: ConsentPolicy(version: '2026-10', purposes: [
      ConsentPurpose(id: 'essential', title: 'Essential', description: '...', required: true),
      ConsentPurpose(id: 'crash_reporting', title: 'Crash reports', description: '...'),
      ConsentPurpose(id: 'analytics', title: 'Analytics', description: '...'),
    ]),
    consentStore: MyConsentStore(),                     // implement ConsentStore
    forwardLogs: (record) => crashReporter.log(record.message),
    forwardLogsPurpose: 'crash_reporting',              // forward only with consent
    serverDeletion: api.deleteAccount,                  // Future<ErasureStatus> Function()
    cloudProjectNumber: 123456789012,                   // Android Play Integrity
  );

  kit.logger.info('Signed in as jane.doe@example.com'); // ... [REDACTED:email]
  kit.consent!.watch('analytics').listen(analytics.setEnabled);
  kit.exporter.register(CallbackDataSource('profile', () async => profileDao.toJson()));
  kit.deletion.register(CallbackDataEraser('profile', () async {
    await profileDao.deleteAll();
    return ErasureStatus.deleted;
  }));

  runApp(MyApp(kit: kit));
}
```

Show the consent prompt with `showConsentDialog(context, manager: kit.consent!)` when `kit.consent!.state.needsConsent` is true.

## API overview

`ComplianceKit.init(...)` returns a `ComplianceKit` with:

| Field | Type |
|---|---|
| `auditTrail` | `AuditTrail` shared by every module (in-memory by default; pass your own) |
| `logger` | `ComplianceLogger` |
| `consent` | `ConsentManager?` (`null` without a consent policy) |
| `exporter` | `DataExporter` (includes the `consent_history` source by default) |
| `deletion` | `DataDeletionManager` |
| `integrity` | `Integrity` |

Every type from the four packages is re-exported. See their READMEs and the [guides](https://github.com/Ahmadhussain0335/compliance_kit/tree/main/docs) for details.

## Limitations

- The default audit trail is in memory. Pass a persistent `AuditTrail` if you need the events as evidence.
- Only an in-memory `ConsentStore` is included; implement one with your storage.
- Integrity tokens must be verified on your server (a reference server is in the repository).
- Platform setup for Play Integrity and App Attest is required; see the compliance_integrity README.

## Disclaimer

Compliance Kit helps developers implement privacy and security controls. It does not by itself make an application compliant with GDPR, the CRA, EN 18031, OWASP MASVS or any other regulation or standard. Compliance depends on the whole system and must be assessed separately.

## License

MIT. See [LICENSE](LICENSE).
