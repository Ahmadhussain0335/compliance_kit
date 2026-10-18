# compliance_gdpr guide

## Designing purposes

- One purpose per processing activity the user can meaningfully choose: `analytics`, `crash_reporting`, `marketing`, `personalisation`.
- Mark a purpose `required` only if it is strictly necessary for the service the user asked for. Required purposes are not consent-based and are shown as "Always active".
- Write titles and descriptions in plain language and localize them. Have them reviewed together with your privacy policy.

## Policy versions

Bump `ConsentPolicy.version` when purposes are added or their meaning changes. Consent given under the old version stops counting; users see the prompt again with a notice. Do not bump it for typo fixes, or users will be asked too often.

## Connecting SDKs

```dart
kit.consent!.watch('analytics').listen((granted) {
  analytics.setCollectionEnabled(granted);
});
```

Make sure SDKs start disabled and are only enabled from `watch`. Many SDKs collect data at initialization; configure them not to.

## Persisting consent

Implement `ConsentStore` with your storage (see the package README for a `SharedPreferences` example). Keep the history append-only. Decide how long to keep records after an account is deleted; `ComplianceKit.init(eraseConsentOnDeletion:)` controls whether they are wiped.

## Export

Register a `DataSource` for every place user data lives: databases, preferences, files, caches, Keychain/Keystore entries that hold user data. Return JSON-encodable data. For sources containing other people's data (support logs, chat transcripts), wrap them in `RedactingDataSource`. Large media files should be delivered separately.

Deliver the JSON file securely, for example through the system share sheet or your backend. Server-side data must be exported by your backend.

## Deletion

1. Implement `serverDeletion` so that it deletes the account on your backend and returns `ErasureStatus.skipped` if the account is already gone.
2. Register a `DataEraser` for every local data location. Make erasers idempotent.
3. Require confirmation in your UI (the API requires a `confirm` callback). Consider re-authentication.
4. Show `DeletionReport` failures to the user and offer `retry`.
5. Remember backups, processors and logs on the server side; this package only covers the device.
