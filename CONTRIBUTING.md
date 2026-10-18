# Contributing

Thanks for helping. Bug reports, documentation fixes and pull requests are welcome. For security issues, follow [SECURITY.md](SECURITY.md) instead of opening an issue.

## Setup

Requirements: Flutter stable (3.47.7 is used in CI) with its bundled Dart SDK. For the native plugin code, Android SDK with Java 17 and Xcode.

```sh
git clone https://github.com/Ahmadhussain0335/compliance_kit.git
cd compliance_kit
flutter pub get                                   # resolves the whole pub workspace
```

## Checks

Run these before opening a pull request. CI runs the same.

```sh
dart format --output=none --set-exit-if-changed .
dart run melos run analyze --no-select            # dart analyze --fatal-infos
dart run melos run test --no-select
dart run melos run coverage --no-select           # pure Dart packages, 90% line coverage minimum
dart run melos run publish-dry-run --no-select

# Native code (when touching compliance_integrity)
cd packages/compliance_integrity/example
flutter build apk --debug && (cd android && ./gradlew :compliance_integrity:testDebugUnitTest)
flutter build ios --simulator --debug
```

After changing `packages/compliance_integrity/pigeons/messages.dart`, regenerate the channel with `dart run pigeon --input pigeons/messages.dart` from that package.

## Rules

- **Fake data only.** Tests, examples and fixtures must never contain real personal data, credentials or keys. Use `example.com` addresses, reserved phone ranges such as `+44 20 7946 0xxx`, card network test numbers and documentation IBANs. Build credential-shaped fixtures from parts at runtime so secret scanners do not flag them.
- **No secrets** in code, logs, tests or documentation.
- **Dartdoc on every public API.** `public_member_api_docs` and `comment_references` are enforced.
- **Tests with every change.** New logic needs unit tests; UI changes need widget tests; redaction rules need false-positive tests as well as positive ones.
- **Dependencies:** open an issue before adding one. The packages keep their dependency footprint small on purpose.
- **Audit events** must never contain personal data, tokens, key ids or masked values.
- **Disclaimer:** every package README keeps the disclaimer section.
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `ci:`, with an optional scope such as `fix(logger):`). Keep commits small and focused.
- **Pull requests** target `main`, describe the change and its risks, and update the relevant `CHANGELOG.md`.

## Releases

Maintainers publish releases following [RELEASE.md](RELEASE.md).

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
