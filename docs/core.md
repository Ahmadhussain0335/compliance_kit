# compliance_core guide

`compliance_core` defines what the other packages share: `AuditEvent`, `AuditTrail` and `ComplianceException`.

## Choosing an AuditTrail

| Implementation | Use |
|---|---|
| `NoopAuditTrail` | You do not need audit events. |
| `InMemoryAuditTrail(maxEvents: n)` | Tests, debugging, or as a buffer you flush yourself. Lost on restart. |
| Your own | Production. Write events to a local database and/or send them to your backend. See [audit-trail.md](audit-trail.md). |

An implementation must be fast and must not throw for valid events. The Compliance Kit packages record events in the background and never wait for them, but a trail that blocks the event loop still slows the app.

## Writing events yourself

You can record your own events in the same trail, for example when an administrator changes a retention setting:

```dart
await trail.record(AuditEvent(
  type: 'retention_changed',
  source: 'my_app',
  metadata: const {'days': 30},
));
```

Rules enforced by `AuditEvent`: lowercase identifiers for `type` and `source`; flat metadata with `String`, `int`, finite `double`, `bool` or `null`; at most 32 entries; strings at most 256 characters. These rules make dumping objects into the trail harder. They cannot stop you from putting an email address into a string, so do not.

## Exceptions

All packages throw subclasses of `ComplianceException` with a stable `code` (`invalid_configuration`, `invalid_state`, `invalid_consent_operation`, `incomplete_redaction`, ...). Messages never contain personal data, and the `cause` is not included in `toString()`.
