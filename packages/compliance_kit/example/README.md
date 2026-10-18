# compliance_kit example

One app using every module through `ComplianceKit.init`, with one shared audit trail:

- consent dialog on first launch and a privacy settings screen;
- an error log with personal data that reaches the console redacted, and is forwarded to a stand-in crash reporter only while "Crash reports" consent is granted;
- an integrity check (Play Integrity / App Attest);
- data export (including the consent history) and account deletion;
- the audit trail with every recorded event.

All data is fake and kept in memory. See the `compliance_integrity` example for Play Integrity and App Attest setup.

```sh
flutter run --dart-define=CLOUD_PROJECT_NUMBER=<your Google Cloud project number>
```
