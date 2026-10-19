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
  compliance_gdpr/         Flutter, deps: compliance_core, compliance_logger. example/ is a workspace member
  compliance_integrity/    Flutter plugin (Pigeon). Android: Play Integrity standard requests (Kotlin). iOS: App Attest (Swift, SwiftPM + CocoaPods). example/ is a workspace member
server/                    reference verification server (Dart + shelf), NOT published, workspace member
  compliance_kit/          umbrella: re-exports all packages + ComplianceKit.init (shared AuditTrail, consent-gated log forwarding). example/ is a workspace member
docs/                      guides per package + audit-trail guide (event catalogue)
RELEASE.md                 publisher setup, publish order, tags, post-release checks
CHANGELOG.md, SECURITY.md, CONTRIBUTING.md   family release notes, vulnerability reporting (GitHub private reporting), contributor rules
```

Packages have no own analysis_options.yaml; the root file applies to all.

## Commands

```sh
flutter pub get                                   # workspace contains Flutter packages; use flutter, not dart, to resolve
dart run melos run analyze --no-select
dart format --output=none --set-exit-if-changed .
dart run melos run test --no-select
cd packages/compliance_gdpr && flutter test --coverage    # Flutter packages use flutter test
cd packages/compliance_integrity/example && flutter build apk --debug && (cd android && ./gradlew :compliance_integrity:testDebugUnitTest)
cd packages/compliance_integrity/example && flutter build ios --simulator --debug
cd server && dart test
dart run melos run coverage --no-select           # fails under 90% line coverage (pure Dart packages)
dart run melos run publish-dry-run --no-select    # never publish for real
sh tool/coverage_summary.sh packages/<pkg>/coverage/lcov.info
dart compile exe packages/compliance_logger/benchmark/redaction_benchmark.dart -o /tmp/bench && /tmp/bench
```

## Conventions

- Conventional commits, small and focused, on feature branches (`feat/phase-N-...`). Never commit to main.
- Dartdoc on every public API; `comment_references` is on, so `[Foo]` must resolve or use backticks.
- Tests and examples use obviously fake data only (`jane.doe@example.com`, `+44 20 7946 0958`, card network test numbers, documentation IBANs).
- Release order: core -> logger -> gdpr + integrity -> kit (see RELEASE.md).
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
- `test` is constrained to ^1.31.1 because the workspace resolves one version set and flutter_test pins test_api 0.7.12.
- GDPR: consent records are append-only (proof of consent); consent from an older policy version does not count; required purposes cannot be withdrawn; deletion runs server first and keeps local data if the server step fails (`eraseLocalWhenServerFails` to override); only InMemoryConsentStore ships (no storage dependency).
- GDPR UI: accept/reject are the same widget, style and width; prompt is not dismissible without a choice; settings toggles apply immediately.
- Integrity: one Dart API with a sealed IntegrityResult; no method throws. Error codes are shared between Dart (IntegrityErrorCodes), Kotlin (IntegrityErrors) and Swift (IntegrityErrorCode) - keep them in sync. Regenerate the channel with `dart run pigeon --input pigeons/messages.dart` (in packages/compliance_integrity).
- iOS clientDataHash = SHA-256(UTF-8(requestHash)); the server must compute the same. App Attest key id + attested flag live in the Keychain (AfterFirstUnlockThisDeviceOnly). invalidKey triggers one automatic re-attestation.
- Android: provider cached per Cloud project number; re-prepared once on INTEGRITY_TOKEN_PROVIDER_INVALID (-19). 60 s timeout per call.
- Server: hand-written DER/X.509 parsing (no asn1lib) + pointycastle ECDSA + cbor. Apple root CA pinned in lib/src/app_attest/apple_root_ca.dart. Apple's sample attestation is a test fixture (valid only at 2026-04-21, so tests inject `now`).
- Approved deps for phase 3: pigeon (dev), meta (Pigeon output), play:integrity 1.6.0, kotlinx-coroutines-android 1.11.0 (Pigeon output), server: googleapis, googleapis_auth, shelf, shelf_router, cbor, pointycastle (asn1lib approved but not used).
- Performance: AOT Dart runs regexes in an interpreter. Alternations, capture groups and `{n,m}` quantifiers on long input are slow; every rule has a cheap literal/char-class prefilter, and generic key detection is a code-unit scan. Re-run the benchmark after changing rules.

## Status

- Phase 1 (monorepo, compliance_core, compliance_logger): done. core 100% / logger 99.7% line coverage. Both pass `dart pub publish --dry-run` with 0 warnings.
- Phase 2 (compliance_gdpr): done on branch feat/phase-2-gdpr (stacked on phase 1). Logger review fixes (redaction bypasses) also landed on this branch as fix(logger).
- Phase 3 (compliance_integrity + server): done on branch feat/phase-3-integrity (stacked on phase 2). Native code compiled locally (debug APK, iOS simulator build); Kotlin unit test passes. Real-device testing still to do (checklist in the package README). GDPR review fixes also landed on this branch.
- Phase 4 (umbrella, docs, release prep): done and merged.
- Beta prep 0.1.0-beta.1 (PR #3): CODE_OF_CONDUCT (Contributor Covenant 3.0), issue forms, PR template, Dependabot, all packages 0.1.0-beta.1 with sibling constraints ^0.1.0-beta.1, dated changelogs, README badges/status/device note/platform table/roadmap. All publish dry-runs 0 warnings. Not published.
- Remote: https://github.com/Ahmadhussain0335/compliance_kit (public). All phases merged to main (PR #1, fast-forward). main is protected: PR required, CI checks "Format, analyze, test", "Android plugin unit tests", "iOS plugin build" must pass, admins included, no force push/deletion. Work on a branch and open a PR. Commits use the personal email (repo-local git config); never the company email. Prefer `gh pr merge --rebase` so no merge commit picks up another email.
- Tags compliance_<pkg>-v0.1.0 on main (3b14e61) with GitHub pre-releases; release notes include a git-dependency snippet with dependency_overrides for siblings (verified). Repo homepage points to docs/ until pub.dev publishing.
- pub.dev: all five packages PUBLISHED as 0.1.0-beta.1 on 2026-10-19 (personal account ahmadhussain0335@gmail.com, order core, logger, gdpr, integrity, kit). Tags compliance_<pkg>-v0.1.0-beta.1 on eb621c2 with GitHub pre-releases; repo homepage = https://pub.dev/packages/compliance_kit. The older compliance_<pkg>-v0.1.0 tags/pre-releases were kept on purpose (owner decision). Next releases: bump versions + CHANGELOG, follow RELEASE.md.
- pana resolves dependencies from pub.dev, so in-workspace runs fail for packages whose siblings are unpublished. Run it on standalone copies with path dependency_overrides (scratch), or after the siblings are published.
- PROMPT.md is untracked and ignored; the local copy stays.
- Open before 1.0.0: real-device integrity tests, testing the declared minimum Flutter 3.35 (only 3.47.7 is tested), verified publisher.
