# Compliance Kit - project guide for Claude Code

Open-source Dart/Flutter package family for privacy and security controls. Full phase plan: `PROMPT.md`.

## Layout

```
pubspec.yaml               pub workspace root + melos 8 config (scripts under `melos:`)
analysis_options.yaml      shared strict lints (strict-casts/inference/raw-types, public_member_api_docs)
tool/coverage_summary.sh   prints line coverage from an lcov file
.github/workflows/ci.yaml  format, analyze, test + coverage on push/PR (actions pinned by SHA)
packages/
  compliance_core/         pure Dart, no deps: AuditEvent, AuditTrail, exceptions
  compliance_logger/       pure Dart, deps: compliance_core, crypto
  compliance_gdpr/         Flutter, skeleton (Phase 2)
  compliance_integrity/    Flutter plugin, skeleton (Phase 3)
  compliance_kit/          umbrella, skeleton (Phase 4)
```

Packages have no own analysis_options.yaml; the root file applies to all.

## Commands

```sh
flutter pub get                                   # workspace contains Flutter packages; use flutter, not dart, to resolve
dart run melos run analyze --no-select
dart format --output=none --set-exit-if-changed .
dart run melos run test --no-select
dart run melos run coverage --no-select           # fails under 90% line coverage (pure Dart packages)
dart run melos run publish-dry-run --no-select    # never publish for real
sh tool/coverage_summary.sh packages/<pkg>/coverage/lcov.info
dart compile exe packages/compliance_logger/benchmark/redaction_benchmark.dart -o /tmp/bench && /tmp/bench
```

## Conventions

- Conventional commits, small and focused, on feature branches (`feat/phase-N-...`). Never commit to main.
- Dartdoc on every public API; `comment_references` is on, so `[Foo]` must resolve or use backticks.
- Tests and examples use obviously fake data only (`jane.doe@example.com`, `+44 20 7946 0958`, card network test numbers, documentation IBANs).
- Credential-shaped fixtures (API keys, PEM blocks) are assembled at runtime from parts, otherwise `dart pub publish` and GitHub secret scanning flag them.
- Ask before adding any dependency. Approved so far: crypto, test, lints, coverage, melos, subosito/flutter-action.
- The disclaimer from PROMPT.md must appear in the root README and every package README.
- Audit event metadata: primitives only, never personal data (enforced partly by `AuditEvent`).

## Decisions

- Package names verified free on pub.dev (2026-10-18). Repository URL: github.com/Ahmadhussain0335/compliance_kit (repo not created yet).
- Flutter 3.47.7 / Dart 3.13.5 stable, melos 8.9.0 (pub workspaces, config in root pubspec). SDK constraint `^3.9.0`.
- Logger hash mode is HMAC-SHA-256 with an app-supplied key (random per-process key if none), not plain SHA-256, because low-entropy values like phone numbers are brute-forceable.
- Built-in rule defaults: all on with full masking, except `ip_address` (off). Partial/hash are opt-in.
- Redaction fails closed: a throwing rule turns the whole string into `[REDACTED:redaction_error]`.
- Performance: AOT Dart runs regexes in an interpreter. Alternations, capture groups and `{n,m}` quantifiers on long input are slow; every rule has a cheap literal/char-class prefilter, and generic key detection is a code-unit scan. Re-run the benchmark after changing rules.

## Status

- Phase 1 (monorepo, compliance_core, compliance_logger): done. core 100% / logger 99.7% line coverage. Both pass `dart pub publish --dry-run` with 0 warnings.
- Phase 2 (compliance_gdpr): not started.
- Phase 3 (compliance_integrity): not started.
- Phase 4 (umbrella, docs, release prep): not started.
