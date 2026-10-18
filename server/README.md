# compliance_integrity reference server

> **Reference example, not production-ready.** It shows how to verify tokens from [`compliance_integrity`](../packages/compliance_integrity). It keeps challenges and keys in memory, has no authentication, rate limiting or request size limits, and has not been audited. Review and adapt it before using any part of it.

Dart + [shelf](https://pub.dev/packages/shelf). Not published to pub.dev.

## What it verifies

### Android: Play Integrity (standard requests)

1. Decodes the token with Google's `decodeIntegrityToken` API (`googleapis`), authenticated with a service account from the Cloud project linked in Play Console.
2. Applies Google's recommended checks (`PlayIntegrityPolicy`):
   - `requestDetails`: package name, `requestHash` equals the issued challenge, `timestampMillis` at most 2 minutes old;
   - `appIntegrity.appRecognitionVerdict == PLAY_RECOGNIZED`, package name, optional signing certificate digests;
   - `deviceIntegrity.deviceRecognitionVerdict` contains `MEETS_DEVICE_INTEGRITY` (configurable, for example `MEETS_STRONG_INTEGRITY`);
   - `accountDetails.appLicensingVerdict == LICENSED` (configurable).

### iOS: App Attest

Follows Apple's [validation steps](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server):

Attestation (`AppAttestVerifier.verifyAttestation`):
1. CBOR `apple-appattest` object; `x5c` chain verified to the pinned **Apple App Attestation Root CA** (`lib/src/app_attest/apple_root_ca.dart`, SHA-256 fingerprint `1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32`). The root is never taken from the request.
2. `SHA-256(authData || clientDataHash)` equals the nonce in certificate extension `1.2.840.113635.100.8.2`.
3. `SHA-256(credential public key)` equals the key id.
4. RP ID hash equals `SHA-256("<TeamID>.<bundleId>")`.
5. Counter is 0.
6. AAGUID matches the environment (`appattest` + 7 zero bytes for production; `appattestdevelop`, or `appattestsandbox` as mentioned on one Apple page, for development).
7. Credential id equals the key id.

Assertion (`AppAttestVerifier.verifyAssertion`): ECDSA P-256 signature over `SHA-256(authenticatorData || clientDataHash)` with the stored key, RP ID hash, and a counter strictly greater than the stored one.

`clientDataHash` is `SHA-256(UTF-8(challenge))`, matching what `compliance_integrity` passes to App Attest.

Not implemented: Apple's newer `apple_validation_category_01` / `apple_bundle_version_01` authenticator data extensions, and the fraud risk metric (the receipt is stored for you to use).

The tests include Apple's published sample attestation from the "Attestation Object Validation Guide" as a test vector.

## API

| Route | Body | Response |
|---|---|---|
| `POST /v1/challenge` | none | `{"challenge": "<base64url, 256 bits>"}`, single use, 5 minutes |
| `POST /v1/android/verify` | `{"token", "challenge"}` | `200 {"ok": true}` or `403 {"ok": false, "failures": [...]}` |
| `POST /v1/ios/attest` | `{"attestation", "keyId", "challenge"}` | same; stores the key on success |
| `POST /v1/ios/assert` | `{"assertion", "keyId", "challenge"}` | same; advances the counter. Unknown key: `409 {"ok": false, "action": "reattest"}` (the app calls `Integrity.reset()`) |

Responses do not say which check failed, so attackers cannot use them to tune forgeries. Failure reasons (`request_hash`, `device_integrity`, `nonce`, `certificate_chain`, `counter`, ...) go to the `onFailure` callback; the entry point writes them to stderr. Set `EXPOSE_FAILURE_REASONS=true` during development to include them in responses. Tokens and key ids are never logged.

Built-in limits: request bodies up to 32 KB, attestations up to 16 KB, assertions up to 1 KB, at most 10,000 outstanding challenges (then `503`), and Android tokens must look like a compact JWE before the Google API is called. Certificate chains must have exactly two certificates; issuers must be CAs allowed to sign certificates, the leaf must not be a CA, and EC public keys are checked to be on the curve.

## Run

```sh
cd server
export ANDROID_PACKAGE_NAME=com.example.app
export ANDROID_CERT_SHA256=<base64url digest from Play Console>   # optional
export GOOGLE_APPLICATION_CREDENTIALS=/secure/path/service-account.json
export IOS_TEAM_ID=ABCDE12345
export IOS_BUNDLE_ID=com.example.app
export IOS_APP_ATTEST_ENV=development   # or production (TestFlight / App Store)
dart run bin/server.dart
```

The server binds to `127.0.0.1` only. Put it behind a TLS-terminating proxy; never expose it over plain HTTP. Never commit the service account key.

## Before production

- Authenticate callers and bind App Attest keys to user accounts; reject a key already bound to another account.
- Store challenges and keys in a shared database (with expiry), not in memory.
- Add authentication and rate limiting (especially on `/v1/challenge` and `/v1/android/verify`, which spends Play Integrity quota), and monitoring.
- App Attest key ids and receipts are persistent per-install identifiers: treat them as personal data (retention, lawful basis, deletion on account erasure).
- Decide your policy for devices that cannot attest (no Google Play services, Macs, simulators): fall back to other risk signals rather than locking users out silently.
- Implement the Apple extensions and receipt refresh if you need them.
- Have the code reviewed.

## Test

```sh
dart test
```
