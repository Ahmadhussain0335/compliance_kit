## 0.1.0

- Initial release.
- `ComplianceLogger` with six levels, lazy messages, child loggers and sink error isolation.
- Redaction of message, error text, stack trace text and structured fields before any sink runs.
- Built-in rules: authorization/bearer, sensitive fields, JWT, API keys, payment cards (Luhn), IBAN (mod-97), email, phone, IPv4/IPv6 (off by default).
- Mask modes: partial, full and keyed hash (HMAC-SHA-256).
- Custom regex and function rules, allowlist, configurable sensitive keys.
- Sinks: `ConsoleSink`, `MemorySink`, `CallbackSink`.
- Optional `log_redaction` audit events through `compliance_core`.
