# compliance_logger guide

## Replace your logger

Create one `ComplianceLogger` per app (or use `ComplianceKit.logger`) and pass child loggers to features:

```dart
final log = ComplianceLogger(name: 'app');
final checkoutLog = log.child('checkout');
```

Everything you pass, including `error` objects, stack traces and `fields`, is redacted before any sink sees it.

## Choosing rule settings

- Start with `BuiltInRules.defaults()`: everything on, full masking, IP addresses off.
- Use `MaskMode.hash` for values you need to correlate across log lines (for example a user's email in a support investigation). Supply a `hashKey` of at least 16 bytes from secure storage if hashes must match across app restarts. Hashed values are still personal data.
- Use `MaskMode.partial` only where the visible part is harmless in your context.
- Turn on `ip_address` if your logs contain client IPs and you do not need them.
- Turn on national phone formats only after checking your logs for false positives.

## Custom rules

Add rules for identifiers specific to your domain, for example customer numbers or device serial numbers (which can be personal data, for example in IoT products):

```dart
Redactor(customRules: [
  RegexRedactionRule(id: 'device_serial', pattern: RegExp(r'\bSN-[0-9A-F]{12}\b')),
]);
```

## Forwarding to crash reporters and analytics

Use `CallbackSink`. Records are already redacted. Gate forwarding on consent (`ComplianceKit.init(forwardLogs:, forwardLogsPurpose:)` does this for you). Do not also pass raw exceptions to the crash reporter outside the logger, or the redaction is bypassed.

## Testing your logging

Use `MemorySink` in tests and assert that no personal data from your fixtures appears in `sink.messages`. Add your own false-positive cases (order numbers, product codes) to make sure useful data is not masked.

## Server-side Dart

The package has no Flutter dependency. The same redactor can clean logs in a Dart backend.
