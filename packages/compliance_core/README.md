# compliance_core

Shared building blocks for the [Compliance Kit](https://github.com/Ahmadhussain0335/compliance_kit) package family: an audit event model, an audit trail interface and common exception types. Pure Dart with no dependencies, so it works in Flutter apps, on the server and on the web.

Most apps do not depend on this package directly. It is pulled in by `compliance_logger`, `compliance_gdpr` and `compliance_integrity`, which record their events through the same `AuditTrail`.

## Install

```sh
dart pub add compliance_core
```

## Quick start

```dart
import 'package:compliance_core/compliance_core.dart';

Future<void> main() async {
  final trail = InMemoryAuditTrail(maxEvents: 1000);
  trail.events.listen((event) => print(event.toJson()));

  await trail.record(
    AuditEvent(
      type: 'consent_granted',
      source: 'my_app',
      metadata: const {'purpose': 'analytics', 'policy_version': 3},
    ),
  );
}
```

## API overview

| Type | Purpose |
|---|---|
| `AuditEvent` | Immutable record of something compliance-relevant: `type`, UTC `timestamp`, `source`, flat `metadata`. JSON round-trip via `toJson` / `fromJson`. |
| `AuditTrail` | Interface with `record(event)` and a broadcast `events` stream. Implement it to persist events to a database, file or backend. |
| `InMemoryAuditTrail` | Keeps events in memory with an optional `maxEvents` cap. For tests, examples and buffering. |
| `NoopAuditTrail` | Discards events. Default when an app does not need an audit trail. |
| `ComplianceException` | Base type for all Compliance Kit exceptions, with a stable `code`. Subtypes: `InvalidAuditEventException`, `InvalidConfigurationException`, `ComplianceStateException`. |

### Metadata rules

`AuditEvent` enforces these rules to make accidental personal data leaks less likely:

- Values must be `String`, `int`, finite `double`, `bool` or `null`. Maps, lists and objects are rejected.
- At most 32 entries; string values at most 256 characters.
- `type` and `source` are lowercase identifiers such as `consent_granted`.
- Exception messages never echo the rejected value.

## Limitations

- The library cannot recognise personal data in metadata. A string such as an email address passes validation. Callers must record counts, categories and result codes, never identifiers of people or devices.
- `InMemoryAuditTrail` loses its events when the process ends. Persisting events, retention periods and access control are the app's responsibility.
- The audit trail is not tamper-evident. If you need integrity guarantees (for example hash chaining or write-once storage), implement them in your own `AuditTrail`.

## Disclaimer

Compliance Kit helps developers implement privacy and security controls. It does not by itself make an application compliant with GDPR, the CRA, EN 18031, OWASP MASVS or any other regulation or standard. Compliance depends on the whole system and must be assessed separately.

## License

MIT. See [LICENSE](LICENSE).
