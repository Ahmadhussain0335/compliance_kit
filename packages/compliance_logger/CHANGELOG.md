## 0.1.0-beta.1 - 2026-10-19

First beta release. APIs may change before 1.0.0.

- `ComplianceLogger` with six levels (`trace` to `fatal`), lazy messages, child loggers and isolated sinks: a failing sink, async sink or error handler never breaks logging or other sinks.
- Redaction of the message, the error's text, the stack trace text and structured fields before any sink runs. The original error object is never passed to sinks.
- Built-in rules, each configurable: authorization headers and bearer/basic credentials, sensitive fields (`password=`, JSON, query strings, bracketed keys, also inside other values), JWTs, API keys (AWS, Google, GitHub, Stripe, Slack, `sk-`, PEM private keys, generic high-entropy keys), payment cards (network prefix + Luhn), IBANs (country length + mod-97), email addresses (including internationalised and URL-encoded), international phone numbers (national formats opt-in), IPv4/IPv6 (off by default).
- Mask modes: partial, full and keyed hash (HMAC-SHA-256 with an app-supplied key).
- Custom regex and function rules, allowlist and allow patterns, configurable sensitive keys.
- Structured values: recursive maps and lists, sensitive map keys, cycle detection, `maxDepth` and `maxCollectionLength` limits (counted as `max_depth` / `truncated`).
- Fails closed: if a rule or a `toString()` throws, the text becomes `[REDACTED:redaction_error]`.
- Sinks: `ConsoleSink`, `MemorySink`, `CallbackSink`.
- Optional `log_redaction` / `log_redaction_failed` audit events through `compliance_core`, with per-rule counts only.
- False-positive tests for versions, dates, timestamps, order ids, UUIDs, hashes, paths and stack frames; benchmark in `benchmark/`.
