# Audit trail guide

Compliance Kit records what happened (consent changes, exports, deletions, redactions, integrity checks) in one `AuditTrail`. This guide explains what is recorded, how to keep it, and how to present it to an auditor.

## What the trail can and cannot show

It can show that the app's controls ran: that consent was asked and recorded with a policy version and timestamp, that a withdrawal took effect, that an export or deletion was requested and completed, and how often logs contained personal data that was masked.

It cannot show that the app is compliant, that SDKs actually stopped collecting data, or what happened on your servers. Combine it with server-side logs, your records of processing activities and your DPIA.

## Event catalogue

All timestamps are UTC. Metadata never contains personal data, tokens or masked values.

| Source | Type | Metadata | Recorded when |
|---|---|---|---|
| `compliance_logger` | `log_redaction` | `level`, `total`, `rule.<rule id>` counts | A log record had values masked |
| `compliance_logger` | `log_redaction_failed` | same | A redaction rule failed and the text was replaced entirely |
| `compliance_gdpr` | `consent_granted` | `purpose`, `policy_version` | The user granted a purpose |
| `compliance_gdpr` | `consent_denied` | `purpose`, `policy_version` | The user declined a purpose not granted before |
| `compliance_gdpr` | `consent_withdrawn` | `purpose`, `policy_version` | The user withdrew a granted purpose |
| `compliance_gdpr` | `consent_policy_changed` | `previous_version`, `policy_version` | At startup, while consent from an older policy is pending |
| `compliance_gdpr` | `data_exported` | `sources`, `failed`, `complete` | An export finished |
| `compliance_gdpr` | `data_deletion_requested` | `server`, `local_steps` | The user confirmed deletion |
| `compliance_gdpr` | `data_deletion_completed` | `complete`, `deleted`, `skipped`, `failed` | A deletion run finished |
| `compliance_integrity` | `integrity_check_passed` | `result`, `kind` | A token was obtained (the server still decides) |
| `compliance_integrity` | `integrity_check_failed` | `result`, `platform_code` | No token was obtained |

The consent records themselves (purpose, decision, timestamp, policy version) are stored by your `ConsentStore` and returned by `ConsentManager.history()`. Those records relate to a person and are personal data; the audit events are not.

## Persisting the trail

`InMemoryAuditTrail` is lost on restart. For evidence, implement `AuditTrail` with durable storage. A minimal append-only JSON Lines file with a hash chain, so that edits and deletions in the middle are detectable:

```dart
class FileAuditTrail implements AuditTrail {
  FileAuditTrail(this.file);
  final File file;
  final _controller = StreamController<AuditEvent>.broadcast();
  String _previousHash = '0' * 64;

  @override
  Stream<AuditEvent> get events => _controller.stream;

  @override
  Future<void> record(AuditEvent event) async {
    final entry = {...event.toJson(), 'prev': _previousHash};
    final line = jsonEncode(entry);
    _previousHash = sha256.convert(utf8.encode(line)).toString();
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    _controller.add(event);
  }
}
```

On startup, read the last line to restore `_previousHash`. Better still, send events to your backend and store them there with access control, because a file on the user's device can be deleted with the app.

Decide a retention period and document it. Audit events contain no personal data by design, but they are linked to a device or account if you upload them with an identifier.

## Producing evidence for an audit

1. Export the trail for the period in question (for example as JSON Lines) together with the hash chain check result.
2. Add the consent policy versions and texts that were live in that period, so `policy_version` values can be resolved.
3. For consent questions about a specific user, export that user's `ConsentManager.history()` from your backend copy, not from the device.
4. Show the configuration: which redaction rules were enabled, which purposes existed, which data sources and erasers were registered.
5. Explain the limits: client-side events show that the app ran the control; server-side logs show what the backend did.

## Monitoring

Useful signals: a rising `log_redaction` rate (someone started logging personal data), any `log_redaction_failed`, `data_deletion_completed` with `complete: false`, and spikes in `integrity_check_failed` by `platform_code`. Pass `onAuditError` to the GDPR managers to detect lost events.
