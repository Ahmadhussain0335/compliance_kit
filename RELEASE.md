# Release checklist

Compliance Kit packages are published manually by the maintainer. Never publish from CI without review.

## 1. One-time setup

- [ ] Create the public GitHub repository `Ahmadhussain0335/compliance_kit` and push `main`. Every pubspec points `repository` and `issue_tracker` there; pub.dev checks that the URLs work.
- [ ] Create a **verified publisher** on pub.dev (requires a domain you control, verified in Google Search Console): pub.dev > your account > Create publisher.
- [ ] After the first upload of each package, transfer it to the publisher: pub.dev > package > Admin > Transfer to publisher.
- [ ] Optional: enable automated publishing from GitHub Actions with OIDC (pub.dev > package > Admin > Automated publishing), tag pattern `<package>-v{{version}}`. Keep manual publishing until the process is stable.
- [ ] Enable GitHub branch protection on `main` (CI required, reviews required).

## 2. Before every release

- [ ] All work merged to `main` through reviewed pull requests; CI green (format, analyze, tests, coverage gate, Android unit tests, iOS build).
- [ ] Versions bumped consistently (Semantic Versioning; while below 1.0.0, a minor bump signals breaking changes). Dependent packages updated to the new constraints, for example `compliance_core: ^0.2.0`.
- [ ] `CHANGELOG.md` of every changed package has an entry for the new version.
- [ ] READMEs, docs/ and examples reflect the release. The disclaimer is present in every README.
- [ ] `dart run melos run publish-dry-run --no-select` reports 0 warnings for every package.
- [ ] Manual device checklist in `packages/compliance_integrity/README.md` done on real Android and iOS devices when integrity code changed.
- [ ] Optional: run `dart pub global activate pana && pana packages/<package>` to preview pub points.

## 3. Publish order

Dependencies must exist on pub.dev before dependents are uploaded:

1. `compliance_core`
2. `compliance_logger`
3. `compliance_gdpr` and `compliance_integrity` (any order)
4. `compliance_kit`

Wait until each package is visible on pub.dev before uploading the next one.

```sh
git checkout main && git pull
git status   # must be clean

cd packages/compliance_core      && dart pub publish && cd ../..
cd packages/compliance_logger    && dart pub publish && cd ../..
cd packages/compliance_gdpr      && flutter pub publish && cd ../..
cd packages/compliance_integrity && flutter pub publish && cd ../..
cd packages/compliance_kit       && flutter pub publish && cd ../..
```

`server/` and every `example/` app have `publish_to: none` and are never published.

## 4. Tag

One tag per published package version:

```sh
git tag -a compliance_core-v0.1.0 -m "compliance_core 0.1.0"
git tag -a compliance_logger-v0.1.0 -m "compliance_logger 0.1.0"
git tag -a compliance_gdpr-v0.1.0 -m "compliance_gdpr 0.1.0"
git tag -a compliance_integrity-v0.1.0 -m "compliance_integrity 0.1.0"
git tag -a compliance_kit-v0.1.0 -m "compliance_kit 0.1.0"
git push origin --tags
```

Create a GitHub release per tag with the CHANGELOG entry.

## 5. After publishing

- [ ] Each package page renders: README, example tab, API docs (dartdoc builds on pub.dev), platforms, topics.
- [ ] Pub points: check the "Scores" tab for each package; fix any reported issue in the next patch release.
- [ ] Install test: create a fresh Flutter app, `flutter pub add compliance_kit`, run the quick start on Android and iOS.
- [ ] Transfer new packages to the verified publisher.
- [ ] Announce, and watch the issue tracker.
- [ ] If a release is broken, publish a fixed patch version and, if needed, retract the broken one (pub.dev > package > Admin > Retract version, possible within 7 days).
