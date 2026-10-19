# compliance_integrity

[![pub version](https://img.shields.io/pub/v/compliance_integrity?include_prereleases)](https://pub.dev/packages/compliance_integrity) [![pub points](https://img.shields.io/pub/points/compliance_integrity)](https://pub.dev/packages/compliance_integrity/score) [![pub likes](https://img.shields.io/pub/likes/compliance_integrity)](https://pub.dev/packages/compliance_integrity/score)

> **Beta: 0.1.0-beta.1.** APIs may change before 1.0.0. Feedback welcome via [GitHub issues](https://github.com/Ahmadhussain0335/compliance_kit/issues).

> **Note:** Not yet verified on physical devices. Play Integrity and App Attest flows are covered by unit tests with mocked platform interfaces only. Please report device results in [GitHub issues](https://github.com/Ahmadhussain0335/compliance_kit/issues).

App and device integrity checks for Flutter, without Firebase:

- **Android**: [Google Play Integrity API](https://developer.android.com/google/play/integrity/overview), standard requests.
- **iOS**: [App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity) (`DCAppAttestService`).

One Dart API, typed results, no exceptions. A reference verification server lives in [`server/`](../../server) in the repository.

> **A token proves nothing on the device.** It must be sent to your server and verified there. Never make security decisions in the app based on whether a token was obtained.

## Install

```sh
flutter pub add compliance_integrity:^0.1.0-beta.1
```

or in `pubspec.yaml`:

```yaml
dependencies:
  compliance_integrity: ^0.1.0-beta.1
```

## Quick start

```dart
final integrity = Integrity(
  cloudProjectNumber: 123456789012, // Android only, from Google Cloud
  auditTrail: auditTrail,           // optional, from compliance_core
);

// Optional warm-up at app start or before a sensitive screen.
await integrity.prepare();

// 1. Get a fresh challenge from your server for this request.
final challenge = await api.getChallenge();

// 2. Request a token bound to it.
switch (await integrity.requestToken(challenge)) {
  case IntegritySuccess(:final token, :final kind, :final keyId):
    // 3. Send it to your server, which decides.
    await api.verifyIntegrity(token: token, kind: kind, keyId: keyId, challenge: challenge);
  case IntegrityUnsupported() || IntegrityPlayServicesMissing():
    // Device cannot attest (simulator, Huawei without Google services, ...).
    // Tell the server; it applies your policy (fallback checks, step-up auth, ...).
  case IntegrityNetworkError() || IntegrityRateLimited():
    // Retry with backoff: 5 s, 10 s, 20 s.
  case IntegrityConfigurationError(:final message):
  case IntegrityPlatformError(:final message):
    // Log and investigate.
}
```

### Why the request hash must come from your server

The request hash (Android `requestHash`, iOS `clientDataHash`) binds a token to one specific request. If the app made it up, an attacker could obtain a valid token once, on a genuine device, and replay it for any later request. A server-issued, single-use challenge with a short lifetime lets the server check that the token was produced for this request, recently, by this app.

- Android: the value is passed unchanged as `requestHash` (at most 500 characters). The server compares `requestDetails.requestHash`. With the reference server, pass the challenge itself. Google recommends binding the token to the request content as well, for example `base64url(SHA-256(challenge || action || payload))`; if you do, your server must compute the same value from the request it receives.
- iOS: the plugin uses `SHA-256(UTF-8(requestHash))` as `clientDataHash`. The server computes the same value.
- Never put personal data in the request hash: Play returns it verbatim in the token.

### iOS: attestation and assertions

App Attest attests a key once and then signs requests with it:

1. The first successful `requestToken` returns `IntegrityTokenKind.appAttestAttestation` and a `keyId`. Your server verifies the attestation and stores the key's public key, bound to the user account.
2. Later calls return `IntegrityTokenKind.appAttestAssertion`. The server verifies the signature with the stored key and checks that the counter increased.
3. If the server does not know the key (it rejected or lost the attestation; the reference server answers `409 {"ok": false, "action": "reattest"}`), call `integrity.reset()` and request again; the next request creates and attests a new key. The plugin marks a key as attested as soon as Apple returns the attestation, so this server signal is the only way to learn that the server never stored it.
4. If Apple rejects a stored key (for example after switching between the development and production environments), the plugin creates and attests a new key automatically. Your server must therefore accept an attestation at any time.

## API overview

| Member | Description |
|---|---|
| `Integrity({cloudProjectNumber, auditTrail})` | Entry point. |
| `isSupported()` | Android: Play Store and Play services installed and enabled. iOS: `DCAppAttestService.isSupported`. Never throws. A `true` result does not guarantee a token. |
| `prepare()` | Android: prepares and caches a standard token provider. iOS: creates a key if none exists. Returns `null` or an `IntegrityFailure`. |
| `requestToken(requestHash)` | Returns an `IntegrityResult`. |
| `reset()` | Discards the cached provider (Android) or the stored key (iOS). |
| `IntegrityResult` | Sealed: `IntegritySuccess`, `IntegrityUnsupported`, `IntegrityPlayServicesMissing`, `IntegrityNetworkError`, `IntegrityRateLimited`, `IntegrityConfigurationError`, `IntegrityPlatformError`. Failures carry `platformCode`, `message` and `isRetryable`. |

### Error mapping

| Platform error | Result |
|---|---|
| Play `API_NOT_AVAILABLE` (-1), `PLAY_STORE_NOT_FOUND` (-2), `PLAY_SERVICES_NOT_FOUND` (-6), `CANNOT_BIND_TO_SERVICE` (-9), `PLAY_STORE_VERSION_OUTDATED` (-14), `PLAY_SERVICES_VERSION_OUTDATED` (-15) | `IntegrityPlayServicesMissing` |
| Play `NETWORK_ERROR` (-3), timeout after 60 s | `IntegrityNetworkError` |
| Play `TOO_MANY_REQUESTS` (-8) | `IntegrityRateLimited` |
| Play `CLOUD_PROJECT_NUMBER_IS_INVALID` (-16), `REQUEST_HASH_TOO_LONG` (-17), missing project number, empty or too long request hash | `IntegrityConfigurationError` |
| Play `GOOGLE_SERVER_UNAVAILABLE` (-12), `CLIENT_TRANSIENT_ERROR` (-18), `INTEGRITY_TOKEN_PROVIDER_INVALID` (-19, after one automatic re-prepare), `INTERNAL_ERROR` (-100) | `IntegrityPlatformError` with `isRetryable: true` |
| Play `APP_NOT_INSTALLED` (-5), `APP_UID_MISMATCH` (-7), others | `IntegrityPlatformError` |
| App Attest unsupported device, `DCError.featureUnsupported` | `IntegrityUnsupported` |
| `DCError.serverUnavailable` | `IntegrityNetworkError` (the same key is kept, as Apple recommends) |
| `DCError.invalidInput` | `IntegrityConfigurationError` |
| `DCError.invalidKey`, `DCError.unknownSystemFailure`, Keychain errors | `IntegrityPlatformError` |
| No native implementation (web, desktop) | `IntegrityUnsupported` |

### Audit events

`integrity_check_passed` when a token was obtained, `integrity_check_failed` otherwise. Metadata: `result`, plus `kind` or `platform_code`. Never the token, key id or request hash. "Passed" only means a token was produced; the server's verdict is what counts.

## Setup

### Google Play Console and Google Cloud (Android)

1. In [Google Cloud Console](https://console.cloud.google.com), create or pick a project and enable the **Play Integrity API**.
2. Note the **project number** (not the project id). Pass it as `cloudProjectNumber`. It is not a secret, but keep it in build configuration (for example `--dart-define`), not hard-coded across environments.
3. In **Play Console > your app > Protected with Play (App integrity) > Play Integrity API**, click **Link Cloud project** and select that project.
4. For server verification, create a **service account** in the same Cloud project and give the server its credentials through Application Default Credentials (`GOOGLE_APPLICATION_CREDENTIALS`). Never ship the key in the app or commit it.
5. Optional, in Play Console: opt in to extra verdicts (`MEETS_STRONG_INTEGRITY`, device activity, app access risk, Play Protect) and configure responses.
6. Quota: 10,000 requests per day across all installs by default. Request an increase in Play Console before launch if needed.
7. Test on a device with Google Play, with the app installed from Play (internal testing track) for `PLAY_RECOGNIZED` and `LICENSED` verdicts. Sideloaded debug builds are typically `UNRECOGNIZED_VERSION`.

Android build facts: `com.google.android.play:integrity:1.6.0` (requires API 23; this plugin's minSdk is 24), `kotlinx-coroutines-android` (required by the Pigeon-generated code). The plugin manifest adds `<queries>` for `com.android.vending` and `com.google.android.gms` so `isSupported()` can see them on Android 11+. No permissions are added.

### Apple Developer account and Xcode (iOS)

1. In **Certificates, Identifiers & Profiles > Identifiers**, enable **App Attest** for your App ID. Regenerate provisioning profiles.
2. In Xcode, add the **App Attest** capability to the Runner target. This writes the entitlement `com.apple.developer.devicecheck.appattest-environment` = `development` to `Runner.entitlements`:
   ```xml
   <key>com.apple.developer.devicecheck.appattest-environment</key>
   <string>development</string>
   ```
3. `development` uses Apple's sandbox. TestFlight, App Store and Enterprise builds always use **production**, whatever the entitlement says. Keys and receipts from the two environments are not interchangeable; configure your server per environment.
4. Your server needs your **Team ID** and **bundle identifier** to check the App ID hash.
5. Minimum iOS version: 15.0 (App Attest itself needs iOS 14). On the simulator and on Macs, App Attest reports unsupported.
6. Roll out gradually: Apple asks to keep `attestKey` below roughly 100 requests per second across all installs.
7. No Info.plist changes are needed. The plugin ships a privacy manifest declaring no tracking, no collected data and no required-reason APIs. Your app's own privacy manifest and App Store privacy answers must reflect what your server does with the tokens.

## Manual real-device test checklist

Run the example app (`example/`) and your server.

| Device | Expected |
|---|---|
| Android phone with Google Play, app from an internal testing track | `IntegritySuccess(playIntegrityStandard)`; server verdict passes (`PLAY_RECOGNIZED`, `MEETS_DEVICE_INTEGRITY`, `LICENSED`). |
| Same, sideloaded debug build | Token obtained; server reports `app_recognition` and possibly `licensing` failures. |
| Same, airplane mode | `IntegrityNetworkError`. |
| Same, wrong `cloudProjectNumber` | `IntegrityConfigurationError` (`platformCode` -16). |
| Android without Google Play services (for example a Huawei device or an AOSP emulator image) | `isSupported() == false`; `IntegrityPlayServicesMissing` (-1, -2 or -6). |
| Android emulator with Google Play image | Token obtained; device verdict usually fails on the server. |
| iPhone, development build with App Attest capability | First request: `appAttestAttestation` with `keyId`; server `/v1/ios/attest` passes in `development` mode. Second request: `appAttestAssertion`; `/v1/ios/assert` passes. |
| iPhone, after deleting and reinstalling the app | A new key is attested (the old Keychain item is not usable). |
| iPhone, TestFlight build | Attestation passes only with the server in `production` mode. |
| iOS simulator | `isSupported() == false`; `IntegrityUnsupported`. |
| iPhone, airplane mode during first attestation | `IntegrityNetworkError`; the next request reuses the same key. |

## Limitations

- Classic Play Integrity requests and Play remediation dialogs (`showDialog`) are not wrapped yet.
- Apple's fraud risk metric (receipt refresh) is not implemented; the server stores the receipt for you to use.
- On Android, `isSupported()` is a heuristic (installed and enabled packages). The request can still fail.
- The plugin stores one App Attest key per app install. If several users share a device, bind keys to accounts on your server and call `reset()` on account switch.
- Token lifetime is not documented by Google. The reference server accepts tokens up to 2 minutes old.

## Disclaimer

Compliance Kit helps developers implement privacy and security controls. It does not by itself make an application compliant with GDPR, the CRA, EN 18031, OWASP MASVS or any other regulation or standard. Compliance depends on the whole system and must be assessed separately.

## License

MIT. See [LICENSE](LICENSE).
