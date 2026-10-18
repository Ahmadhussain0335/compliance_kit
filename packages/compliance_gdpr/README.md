# compliance_gdpr

GDPR building blocks for Flutter apps:

- **Consent management**: granular consent per purpose, policy versioning, append-only history and change streams.
- **Consent UI**: a dialog or bottom sheet and a privacy settings screen. Accept and reject have equal visual weight, all strings can be overridden, and the UI works with screen readers and large text.
- **Data export** ("export my data"): collects data from every registered source into one JSON document.
- **Account deletion** ("delete my account"): calls your backend, wipes every registered local source and reports the result per step.
- **Audit events** for every consent change, export and deletion through [`compliance_core`](../compliance_core). Event metadata never contains personal data.

## Install

```sh
flutter pub add compliance_gdpr
```

## Quick start

### Consent

```dart
final consent = ConsentManager(
  policy: ConsentPolicy(
    version: '2026-10', // bump when purposes or their texts change materially
    purposes: [
      ConsentPurpose(id: 'essential', title: 'Essential', description: '...', required: true),
      ConsentPurpose(id: 'analytics', title: 'Analytics', description: '...'),
      ConsentPurpose(id: 'marketing', title: 'Marketing', description: '...'),
    ],
  ),
  store: MyPersistentConsentStore(), // implement ConsentStore
  auditTrail: auditTrail,            // optional
);
await consent.initialize();

if (consent.state.needsConsent) {
  await showConsentDialog(context, manager: consent);
}

// React immediately, e.g. stop analytics when consent is withdrawn.
consent.watch('analytics').listen(analytics.setCollectionEnabled);

// One call to withdraw:
await consent.withdraw('analytics');
```

Open the settings screen from your app's settings:

```dart
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => PrivacySettingsScreen(manager: consent),
));
```

### Export

```dart
final exporter = DataExporter(appId: 'com.example.app', auditTrail: auditTrail)
  ..register(CallbackDataSource('profile', () async => profileDao.toJson()))
  ..register(CallbackDataSource('orders', () async => ordersDao.allAsJson()))
  ..register(RedactingDataSource(
    CallbackDataSource('support_log', () async => supportLog.lines()),
    Redactor(), // from compliance_logger: removes other people's emails, phones, ...
  ));

final export = await exporter.export(onProgress: (p) => print(p.fraction));
final json = export.toJsonString();
// Write json to a file named export.suggestedFileName and share it.
if (!export.isComplete) {
  // export.failures lists the sources that failed and why.
}
```

The document looks like this:

```json
{
  "schema_version": 1,
  "app_id": "com.example.app",
  "export_date": "2026-10-18T12:00:00.000Z",
  "complete": false,
  "sources": ["profile", "orders"],
  "data": {
    "profile": {"status": "ok", "data": {"...": "..."}},
    "orders": {"status": "failed"}
  }
}
```

### Deletion

```dart
final deletion = DataDeletionManager(
  serverDeletion: () => api.deleteAccount(), // throw on failure
  auditTrail: auditTrail,
)
  ..register(CallbackDataEraser('database', () async {
    await db.deleteAll();
    return ErasureStatus.deleted;
  }))
  ..register(CallbackDataEraser('preferences', () async {
    await prefs.clear();
    return ErasureStatus.deleted;
  }));

final report = await deletion.deleteAll(
  confirm: () => showMyConfirmationDialog(context), // return false to cancel
);
if (!report.isComplete) {
  final again = await deletion.retry(report); // only failed steps run
}
```

Flow: confirmation, then `data_deletion_requested`, then the server callback, then each local eraser, then `data_deletion_completed`. If the server step fails, local data is kept by default so the signed-in user can retry. Set `eraseLocalWhenServerFails: true` to change that.

## API overview

| Type | Purpose |
|---|---|
| `ConsentPurpose`, `ConsentPolicy` | Purposes defined by the app, and the policy version. |
| `ConsentManager` | `initialize`, `state`, `isGranted`, `grant`, `withdraw`, `acceptAll`, `rejectAll`, `update`, `changes`, `watch`, `history`. |
| `ConsentState`, `ConsentStatus` | Snapshot: `needsConsent`, `status` (`notAsked`, `policyChanged`, `incomplete`, `upToDate`), `isGranted`. |
| `ConsentRecord`, `ConsentStore`, `InMemoryConsentStore` | Stored decisions: purpose id, granted or denied, UTC timestamp, policy version. |
| `showConsentDialog`, `showConsentBottomSheet`, `ConsentPrompt`, `PrivacySettingsScreen`, `ConsentChoiceButtons`, `ConsentStrings` | UI. |
| `DataExporter`, `DataSource`, `CallbackDataSource`, `RedactingDataSource`, `DataExport` | Export. |
| `DataDeletionManager`, `DataEraser`, `CallbackDataEraser`, `DeletionReport` | Deletion. |
| `GdprAuditEvents` | Audit event type constants. |

### Consent rules implemented

- Nothing optional is enabled by default. `isGranted` is `false` until the user grants the purpose.
- Purposes marked `required` are always active and cannot be withdrawn. Use this only for processing that is strictly necessary for the service.
- Consent given under an older policy version does not count. `state.status` becomes `policyChanged` and `isGranted` returns `false` until the user decides again.
- Records are append-only, so `history()` can show when consent was given and withdrawn.

### UI design rules

- "Accept all" and "Reject all" use the same widget, the same style and the same width. A custom `buttonStyle` is applied to both.
- The prompt cannot be dismissed without a choice; rejecting is one tap.
- Withdrawing in the settings screen is a single toggle that applies immediately.
- Buttons stack vertically on narrow screens or with large text. Headings are marked for screen readers, and switches carry the purpose title as their label.
- The widgets use your `Theme`. Override any text with `ConsentStrings` (pass localized strings from your l10n setup).

## Persistent storage

Only `InMemoryConsentStore` is included, to avoid forcing a storage dependency. Implement `ConsentStore` with your storage, for example:

```dart
class PrefsConsentStore implements ConsentStore {
  PrefsConsentStore(this.prefs);
  final SharedPreferences prefs;
  static const _key = 'consent_records';

  @override
  Future<List<ConsentRecord>> load() async => [
        for (final e in jsonDecode(prefs.getString(_key) ?? '[]') as List)
          ConsentRecord.fromJson(e as Map<String, Object?>),
      ];

  @override
  Future<void> append(List<ConsentRecord> records) async {
    final all = [...await load(), ...records];
    await prefs.setString(_key, jsonEncode([for (final r in all) r.toJson()]));
  }

  @override
  Future<void> clear() => prefs.remove(_key);
}
```

## What you still have to do

This package handles the mechanics. Your app and organisation still need to:

- Write the purpose texts, the privacy policy and the legal basis for each processing activity. Have them reviewed.
- Decide which purposes are strictly necessary. Do not mark something `required` to avoid asking for consent.
- Make sure analytics, crash reporting and marketing SDKs actually stop when consent is not granted (use `watch`), and do not start before the user decides.
- Implement a persistent `ConsentStore` and decide how long to keep consent records.
- Implement server-side deletion and export: the backend must delete or export the user's server data, including backups and data held by processors, within the legal deadlines.
- Register every local data location as a `DataSource` and a `DataEraser` (databases, preferences, files, caches, keychain/keystore entries).
- Verify the user's identity before export or deletion where needed, and deliver the export securely.
- Keep the audit trail somewhere durable if you need it as evidence.

## Limitations

- Consent is stored per device and app install. Syncing consent across devices or with a backend is up to the app.
- `RedactingDataSource` is pattern-based and cannot find names or free-text personal data.
- Export holds all data in memory. Very large exports (media files) should be delivered separately, for example as download links.
- The UI uses Material widgets. Cupertino apps can build their own UI on `ConsentManager`.

## Disclaimer

Compliance Kit helps developers implement privacy and security controls. It does not by itself make an application compliant with GDPR, the CRA, EN 18031, OWASP MASVS or any other regulation or standard. Compliance depends on the whole system and must be assessed separately.

## License

MIT. See [LICENSE](LICENSE).
