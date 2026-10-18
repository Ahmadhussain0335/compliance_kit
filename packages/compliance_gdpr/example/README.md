# compliance_gdpr example

A small Flutter app that shows the full flow:

1. The consent dialog appears on first launch (accept all, reject all, or choose individually).
2. The home screen starts or stops "analytics" immediately when consent changes.
3. "Privacy settings" lets the user withdraw any consent with one toggle.
4. "Export my data" builds the JSON export. The support log source is redacted with `compliance_logger` so other people's data is not exported.
5. "Delete my account" asks for confirmation, calls a simulated backend, wipes local data and shows the per-step report.
6. "Show audit trail" lists the recorded events. They contain no personal data.

All data in the app is fake and kept in memory.

```sh
flutter run
```
