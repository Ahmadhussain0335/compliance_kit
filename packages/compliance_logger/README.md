# compliance_logger

A PII-redacting logger for Dart and Flutter. Every message, error, stack trace and structured field passes through a redactor **before** any sink receives it. Emails, phone numbers, tokens, API keys, payment card numbers and IBANs are masked by default.

Pure Dart: works in Flutter apps, on the server and on the web.

## Install

```sh
dart pub add compliance_logger
```

## Quick start

```dart
import 'package:compliance_logger/compliance_logger.dart';

final log = ComplianceLogger(name: 'checkout');

void main() {
  log.info('Receipt sent to jane.doe@example.com');
  // 2026-10-18T12:00:00.000Z [INFO] checkout: Receipt sent to [REDACTED:email]

  log.warning('Payment failed', fields: {
    'card': '4111 1111 1111 1111',
    'password': 'not-a-real-password',
    'attempt': 2,
  });
  // ... Payment failed {"card":"[REDACTED:credit_card]","password":"[REDACTED:sensitive_key]","attempt":2}
}
```

### Configuring rules

```dart
final log = ComplianceLogger(
  redactor: Redactor(
    rules: BuiltInRules.defaults(
      email: const RuleSettings(mode: MaskMode.partial), // j***@example.com
      phone: const RuleSettings(mode: MaskMode.hash),    // [HASH:phone:3f9a1c2b7d10]
      ipAddress: const RuleSettings(),                   // turn on IP masking
      jwt: RuleSettings.disabled,
    ),
    customRules: [
      RegexRedactionRule(id: 'customer_id', pattern: RegExp(r'CUST-\d{8}')),
    ],
    allowlist: {'support@example.com'},
    sensitiveKeys: SensitiveKeys.defaults.withAdditional(exact: ['dob']),
    hashKey: keyFromSecureStorage, // see "Hash mode" below
  ),
);
```

### Forwarding to Crashlytics, Sentry and others

```dart
ComplianceLogger(
  sinks: [
    const ConsoleSink(),
    CallbackSink((record) {
      // record is already redacted
      crashReporter.log('${record.level.label} ${record.message}');
    }),
  ],
);
```

The package has no dependency on any crash reporting or analytics service.

### Audit trail

```dart
final trail = InMemoryAuditTrail(); // from compliance_core
final log = ComplianceLogger(auditTrail: trail);
log.info('mail jane.doe@example.com');
// trail receives: log_redaction {level: info, total: 1, rule.email: 1}
```

Events contain counts per rule only, never the masked values. A rule failure records `log_redaction_failed`.

## API overview

| Type | Purpose |
|---|---|
| `ComplianceLogger` | `trace`, `debug`, `info`, `warning`, `error`, `fatal`, `log`, `child`, `close`. Messages may be a `String Function()` for lazy evaluation. |
| `LogLevel` | Six levels with `isAtLeast`. |
| `LogRecord` | What sinks receive: redacted `message`, `error`, `stackTrace`, `fields` and per-rule `redactions`. The original error object is never passed on. |
| `LogSink`, `ConsoleSink`, `MemorySink`, `CallbackSink` | Destinations. |
| `Redactor` | `redact(String)` and `redactValue(Object?)` for recursive maps and lists. Usable without the logger. |
| `BuiltInRules.defaults` | The built-in rule set, each rule configurable with `RuleSettings`. |
| `RedactionRule`, `RegexRedactionRule`, `FunctionRedactionRule` | Write your own rules. |
| `MaskMode` | `partial`, `full`, `hash`. |
| `SensitiveKeys` | Map keys and `key=value` names whose values are always masked. |

## Built-in rules

Rules run in this order. Text replaced by one rule is not seen by later rules.

| id | Default | Detects | Partial mode |
|---|---|---|---|
| `bearer_token` | on | `Authorization:` header values, `Bearer <token>`, `Basic <base64 user:pass>` | full mask |
| `sensitive_field` | on | `password=…`, `?token=…`, `"secret": "…"`, `pin: 1234` using `SensitiveKeys` | full mask |
| `jwt` | on | `eyJ….eyJ….sig` | header kept |
| `api_key` | on | AWS, Google, GitHub, Stripe, Slack, `sk-` keys, PEM private keys, generic high-entropy strings (32+ chars, mixed case and digits, entropy ≥ 4 bits/char) | first 4 chars |
| `iban` | on | Country-specific length and mod-97 checksum | `DE****3000` |
| `credit_card` | on | 13-19 digits, known network prefix, Luhn checksum | `****1111` |
| `email` | on | Email addresses | `j***@example.com` |
| `phone` | on | International numbers with `+` or `00` (8-15 digits). National formats with `matchNationalPhoneNumbers: true` | `+44********58` |
| `ip_address` | **off** | IPv4 (octets ≤ 255) and IPv6 (validated) | `192.168.*.*` |

Additional behaviour:

- **Structured fields**: values under keys such as `password`, `token`, `secret`, `authorization`, `apiKey`, `cookie`, `pin`, `otp` (see `SensitiveKeys.defaults`) are replaced by `[REDACTED:sensitive_key]` whatever their type. Other strings are redacted with the rules. Integers are checked too, so a card number stored as `int` is masked. Cycles and nesting deeper than `maxDepth` are handled.
- **Fail closed**: if a rule throws, the whole string becomes `[REDACTED:redaction_error]`. The raw text is never used as a fallback.
- **False positives**: the test suite checks that version numbers, dates, ISO timestamps, epoch times, order ids, UUIDs, git hashes, file paths and stack frames are not changed.

### Hash mode

`MaskMode.hash` outputs `[HASH:<rule>:<12 hex chars>]`, the prefix of an HMAC-SHA-256 of the value. Equal values give equal hashes, so you can correlate log lines without seeing the value.

A plain SHA-256 is not used because phone numbers, card numbers and many emails can be recovered by hashing every candidate. The HMAC key prevents this as long as it stays secret.

- If you do not pass `hashKey`, a random key is generated per process. Hashes are then comparable only within one app run.
- To compare across runs or devices, pass a key of at least 16 bytes loaded from secure storage (Keychain, Android Keystore-backed storage, or a server secret). Do not hard-code it.
- Hashed values are pseudonymised, not anonymised. Under GDPR they are still personal data.

## Performance

Regular expressions are compiled once. Each rule first runs a cheap check and skips text that cannot contain a match. Results from `benchmark/redaction_benchmark.dart`, all built-in rules enabled except `ip_address`, on an Intel Core i5-1038NG7 (2.0 GHz) with Dart 3.13.5:

| Case | AOT (µs/op) | JIT (µs/op) |
|---|---|---|
| Clean short message (52 chars) | 3.5 | 4.7 |
| Message with 4 PII values (130 chars) | 29.0 | 27.5 |
| Clean 3.5 KB message | 42.9 | 52.5 |
| `redactValue` on a nested map | 40.7 | 42.1 |
| `logger.info` with PII, null sink | 25.4 | 25.9 |

Run it yourself:

```sh
dart run benchmark/redaction_benchmark.dart
# or, for AOT numbers:
dart compile exe benchmark/redaction_benchmark.dart -o bench && ./bench
```

## Limitations

- Pattern-based detection cannot find all personal data. Names, postal addresses, free-text health information and national ID numbers are not detected. Add custom rules for identifiers specific to your app, and avoid logging personal data in the first place.
- Unquoted values with spaces (`password: my secret`) are masked only up to the first space. Quoted values are masked completely.
- National phone formats are off by default because they collide with other numbers. Enabling them increases false positives.
- A 16-digit number with a valid card prefix passes the Luhn check about one time in ten, so some order ids may be masked. Over-redaction is the chosen failure direction.
- The `ip_address` rule masks four-part version numbers such as `1.2.3.4`.
- Only the redacted text reaches sinks, so you lose the original exception type in sinks. Log what you need explicitly.
- Redaction runs synchronously on the calling isolate. Very large messages cost proportionally more time.

## Disclaimer

Compliance Kit helps developers implement privacy and security controls. It does not by itself make an application compliant with GDPR, the CRA, EN 18031, OWASP MASVS or any other regulation or standard. Compliance depends on the whole system and must be assessed separately.

## License

MIT. See [LICENSE](LICENSE).
