# Compliance Kit - Build Instructions for Claude Code

## How to use this file
This file contains the full plan for the project, split into phases.
Execute ONLY the phase I tell you to run (for example: "Read PROMPT.md and run Phase 1").
Never start the next phase on your own. At the end of every phase, stop and give me a summary.

---

## Project context (applies to all phases)

I am a senior mobile developer (Android/iOS/Flutter) who works daily under GDPR, RED DA / EN 18031, CRA, and OWASP MASVS. This folder is the root of the project.

Compliance Kit is an open-source Flutter/Dart package family that helps apps handle privacy and security requirements:

1. compliance_core       - shared config, error types, audit trail interface (pure Dart)
2. compliance_logger     - PII-redacting logger (pure Dart)
3. compliance_gdpr       - consent, data export, account deletion flows (Flutter)
4. compliance_integrity  - Play Integrity (Android) + App Attest (iOS), no Firebase (Flutter plugin)
5. compliance_kit        - umbrella package that depends on and re-exports all of the above

### Global rules (apply to every phase)
- Work in small steps and commit after each logical step (conventional commits).
- Run analyze and tests after each step and fix issues before continuing.
- Ask me before adding any third-party dependency.
- Never invent the behavior of external APIs (Google, Apple, pub.dev). Check the official documentation; if unsure, tell me.
- Never store, log or include real personal data in tests, examples or fixtures. Use obviously fake values.
- Do NOT publish anything to pub.dev. Only run `dart pub publish --dry-run`.
- Keep CLAUDE.md updated at the end of every phase (status, decisions, commands).
- Before implementing anything in a phase, show me a short plan and wait for my approval.

### Disclaimer (must appear in the root README and every package README)
"Compliance Kit helps developers implement privacy and security controls. It does not by itself make an application compliant with GDPR, the CRA, EN 18031, OWASP MASVS or any other regulation or standard. Compliance depends on the whole system and must be assessed separately."

### Quality bar (applies to every package)
- Dartdoc comments on every public API
- Unit tests with at least 90 percent line coverage for pure Dart packages
- A runnable example/ folder
- README with: install, quick start, API overview, limitations, disclaimer
- CHANGELOG.md and LICENSE (MIT, author: Ahmad Hussain)
- `dart pub publish --dry-run` passes with no warnings

---

## Phase 1 - Monorepo, compliance_core, compliance_logger

### Before writing any code
1. Check on pub.dev whether the names compliance_kit, compliance_core, compliance_logger, compliance_gdpr and compliance_integrity are free. If any are taken, stop and propose an alternative common prefix for all packages, and wait for my choice.
2. Check the current stable Dart/Flutter SDK and melos versions and use them. Use Dart pub workspaces if the current melos version supports them.
3. Show me a plan (folder structure, public API of compliance_core and compliance_logger, list of redaction rules) and wait for my approval.

### Monorepo setup
- melos workspace at the root, with scripts: analyze, format, test, coverage, publish-dry-run
- Strict analysis_options.yaml shared by all packages (strict-casts, strict-inference, strict-raw-types, plus a recommended lint set)
- git init, .gitignore for Dart/Flutter
- GitHub Actions workflow: format check, analyze, test with coverage on every push and PR
- Root README explaining the family and which package to use for what
- CLAUDE.md at the root describing the project, conventions, commands and current status
- Skeletons only for compliance_gdpr, compliance_integrity and compliance_kit: pubspec, README with "planned" status, empty lib entry file. Do NOT implement them in this phase.

### compliance_core
- AuditEvent model: type, timestamp (UTC), source package, optional metadata map (metadata must never contain raw PII)
- AuditTrail abstract interface with record(event) and a stream of events
- InMemoryAuditTrail default implementation
- Shared exception types
- Pure Dart, zero dependencies if possible

### compliance_logger
- Pure Dart, no Flutter dependency, works in Flutter and server Dart
- Log levels: trace, debug, info, warning, error, fatal
- Redaction runs BEFORE any sink receives the message, including error messages and stack trace text
- Built-in redaction rules, each individually enable/disable-able:
  - Email addresses
  - Phone numbers (international formats)
  - JWTs
  - Bearer tokens and Authorization header values
  - Common API key patterns (generic high-entropy keys, AWS-style keys)
  - Credit card numbers (validate with Luhn to reduce false positives)
  - IBANs (validate checksum)
  - IPv4 and IPv6 addresses (off by default)
  - Password fields in key=value, JSON and query-string forms
- Masking modes per rule:
  - partial, for example a***@mail.com
  - full, for example [REDACTED:email]
  - hash, a stable SHA-256 prefix so the same value can be correlated without being revealed
- Custom rules: developers can add their own regex or function-based rules
- Allowlist for values that must never be redacted
- Structured logging: redact values inside maps and lists recursively, matching sensitive keys (password, token, secret, authorization, etc., configurable)
- Sinks: console sink, in-memory sink (for tests), callback sink (so users can forward to Crashlytics, Sentry, etc.). No direct dependency on those services.
- Optional integration with compliance_core AuditTrail: record an event when redaction happens (count and rule type only, never the original value)
- Performance: precompiled regexes; include a simple benchmark in benchmark/ and report results in the README
- Safe failure: if a rule throws, fall back to full redaction of the message, never to the raw message
- Tests must include false-positive cases: version numbers, dates, timestamps, order IDs and UUIDs must not be redacted as phone or card numbers

### End of Phase 1
Give me: what was built, test and coverage results, benchmark numbers, and the remaining steps before publishing compliance_core and compliance_logger.

---

## Phase 2 - compliance_gdpr

### Before writing any code
Show me the public API, the consent data model, and the export and deletion flows. Wait for my approval.

### Consent management
- Consent purposes defined by the app (for example analytics, crash_reporting, marketing), each with id, title, description and whether it is required
- Granular consent per purpose; nothing is enabled by default except purposes marked as strictly necessary
- Consent records store: purpose id, granted or denied, timestamp (UTC), consent policy version
- When the app's consent policy version changes, the package reports that consent must be asked again
- Withdrawing consent must be as easy as giving it (one API call, and one action in the provided UI)
- Stream or listener API so the app can react immediately (for example stop analytics when consent is withdrawn)
- Storage via an abstract ConsentStore interface, with an in-memory implementation included. Ask me before adding any persistent storage dependency.

### Optional consent UI (Flutter widgets)
- A consent dialog or bottom sheet and a "privacy settings" screen
- Fully themeable and localizable; all user-facing strings overridable
- Equal visual weight for "accept" and "reject" options (no dark patterns)
- Accessible: semantic labels, works with screen readers and large text

### Data export ("export my data")
- DataSource registry: the app registers each place it stores user data (database, preferences, files, cache)
- Each source returns its data in a serializable form
- Export produces one JSON file with metadata (export date, app id, schema version, list of sources)
- Optional: use compliance_logger redaction rules to remove third-party personal data from exported logs
- Progress reporting and a clear error per source if one fails, without failing the whole export silently

### Account and data deletion ("delete my account")
- DataEraser registry: the app registers how each local source is wiped
- Hook for server-side deletion: the app provides a callback that calls its backend; the package handles the flow and result
- Deletion result report per source (deleted, failed, skipped) so the app can retry
- Idempotent: running deletion twice must not crash
- Confirmation step support in the API (the app decides how to confirm)

### Audit trail
Record events through compliance_core: consent_granted, consent_withdrawn, consent_policy_changed, data_exported, data_deletion_requested, data_deletion_completed. Never include personal data in event metadata.

### Tests
- Unit tests for consent logic, policy version changes, export and deletion flows
- Widget tests for the consent UI, including accept, reject and withdraw paths
- Example app showing a full consent, export and delete flow

### End of Phase 2
Give me a summary, test and coverage results, and a list of anything a developer must still do themselves (for example legal text, privacy policy, server-side deletion).

---

## Phase 3 - compliance_integrity

### Before writing any code
1. Read the current official documentation for Google Play Integrity API and Apple App Attest (DeviceCheck framework).
2. Show me the plan: Dart API, platform channel approach (prefer Pigeon for type-safe channels; ask me first), native setup steps for Android and iOS, and the server-side verification design.
3. Wait for my approval.

### Dart API
- One API for both platforms, for example:
  - `Integrity.isSupported()`
  - `Integrity.prepare()` (warm-up where the platform supports it)
  - `Integrity.requestToken(nonce or request hash)` returning a typed result
- Typed results and errors: success, unsupported device, Play services missing (for example Huawei devices), network error, rate limited, platform error. Never throw raw platform exceptions to the app.
- The nonce or request hash must come from the app's server; document why.

### Android
- Use the Play Integrity API (standard requests where appropriate; follow current Google guidance on standard vs classic requests)
- Configuration for the Google Cloud project number
- No Firebase dependency
- Graceful handling on devices without Google Play services

### iOS
- Use App Attest via DCAppAttestService: key generation, attestation, and assertions
- Handle unsupported cases (simulator, older devices) with a clear unsupported result
- Document the required App Attest entitlement and the development vs production environment
- Store the attested key id securely (Keychain)

### Server-side verification (reference only)
- Tokens are useless unless verified on the server. Provide a reference server example in a separate folder (Dart with shelf, unless I choose another language).
- Android: decode and verify the Play Integrity token using Google's official server API, and show how to check the verdict fields
- iOS: verify the App Attest attestation and assertions following Apple's documented steps
- Clearly mark this as a reference example, not production-ready code

### Tests
- Unit tests for the Dart layer with a mocked platform interface
- A manual real-device test checklist in the README (Android with Play services, Android without Play services, iPhone, iOS simulator)

### Audit trail
Record integrity_check_passed and integrity_check_failed events through compliance_core (result type only, never the token).

### End of Phase 3
Give me a summary, test results, and the exact setup steps a developer must do in the Google Play Console, Google Cloud, and Apple Developer account.

---

## Phase 4 - compliance_kit umbrella and release preparation

### Before writing any code
Show me the plan for the umbrella API, documentation and release order. Wait for my approval.

### compliance_kit
- Depends on compliance_core, compliance_logger, compliance_gdpr and compliance_integrity
- Re-exports their public APIs
- Optional one-call setup, for example `ComplianceKit.init(...)`, that wires the logger, GDPR module and integrity module to one shared AuditTrail
- Example app showing all modules working together

### Documentation
- Root README: overview, "which package do I need" table, quick start for each package, disclaimer
- A docs/ folder with one guide per package and an "audit trail" guide explaining how to show auditors the recorded events
- Consistent pub.dev metadata in every package: description, repository, issue tracker, topics (for example privacy, security, gdpr, logging, compliance)

### Release preparation (do not publish)
- Version alignment and CHANGELOG entries for every package
- Release order that respects dependencies: compliance_core, then compliance_logger, then compliance_gdpr and compliance_integrity, then compliance_kit
- `dart pub publish --dry-run` passes for every package
- A RELEASE.md checklist: verified publisher setup on pub.dev, tagging, publish order, and post-release checks

### End of Phase 4
Give me a final summary of the whole project, pub.dev score risks (anything that could lower pub points), and the exact commands for me to publish each package myself.
