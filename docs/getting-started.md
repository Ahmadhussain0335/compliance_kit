# Getting started

## Which package do I need?

| Need | Package |
|---|---|
| Logs must not leak emails, phone numbers, tokens, card numbers or IBANs | `compliance_logger` (pure Dart, also for servers) |
| Ask for and record consent, let users withdraw it, export and delete their data | `compliance_gdpr` |
| Check that requests come from your genuine app on a genuine device | `compliance_integrity` + your server |
| A shared audit trail for the above | `compliance_core` (pulled in automatically) |
| All of the above with one setup call | `compliance_kit` |

## One-call setup

```dart
final kit = await ComplianceKit.init(
  appId: 'com.example.app',
  auditTrail: MyPersistentAuditTrail(),        // see audit-trail.md
  consentPolicy: policy,
  consentStore: MyConsentStore(),              // see gdpr.md
  forwardLogs: (r) => crashReporter.log(r.message),
  forwardLogsPurpose: 'crash_reporting',
  serverDeletion: api.deleteAccount,
  cloudProjectNumber: 123456789012,
);
```

Then:

1. Show the consent prompt if `kit.consent!.state.needsConsent`, before starting any SDK that needs consent.
2. Start and stop optional SDKs from `kit.consent!.watch(purposeId)`.
3. Register every place you store user data with `kit.exporter.register(...)` and `kit.deletion.register(...)`.
4. Use `kit.logger` everywhere instead of `print` or other loggers.
5. Call `kit.integrity.requestToken(challenge)` before sensitive requests and verify on the server.

## Recommended order of adoption

1. Logger first: it is low risk and removes the most common leak (personal data in logs and crash reports).
2. Consent, with real purpose texts reviewed by whoever owns your privacy policy.
3. Export and deletion, together with the server-side counterparts.
4. Integrity checks, rolled out in report-only mode on the server first, then enforced.
