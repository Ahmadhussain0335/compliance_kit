## Summary

<!-- What does this change and why? Link related issues. -->

## Packages affected

- [ ] compliance_core
- [ ] compliance_logger
- [ ] compliance_gdpr
- [ ] compliance_integrity
- [ ] compliance_kit
- [ ] server / docs / CI

## Checklist

- [ ] `dart format`, `dart run melos run analyze --no-select` and `dart run melos run test --no-select` pass locally
- [ ] New or changed logic has tests; no tests were skipped, weakened or deleted
- [ ] Redaction changes include false-positive tests
- [ ] Tests, examples and docs use fake data only; no secrets, tokens or keys
- [ ] Public APIs have dartdoc; README and docs/ updated where behaviour changed
- [ ] `CHANGELOG.md` of each affected package updated
- [ ] Audit events contain no personal data, tokens or key ids
- [ ] No new dependency, or it was discussed in an issue first

## Risks

<!-- Breaking changes, migration notes, security or privacy impact. -->
