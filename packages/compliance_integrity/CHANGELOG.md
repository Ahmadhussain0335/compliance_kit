## 0.1.0

Initial release.

- `Integrity` with `isSupported`, `prepare`, `requestToken` and `reset`. No method throws.
- Typed results (`IntegrityResult`, sealed): success, unsupported, Play services missing, network error, rate limited, configuration error, platform error; failures carry the platform code and a retry hint.
- Android: Play Integrity standard requests (`com.google.android.play:integrity` 1.6.0), token provider cached per Cloud project number and re-prepared automatically when invalid, 60 s timeout, no Firebase.
- iOS: App Attest key generation, attestation and assertions; key id stored in the Keychain (this device only, never backed up); automatic re-attestation when Apple rejects a key; requests serialized.
- Type-safe platform channel generated with Pigeon; Swift Package Manager and CocoaPods support; privacy manifest included.
- `integrity_check_passed` / `integrity_check_failed` audit events with the result type only, never the token.
- Documentation of server verification, platform setup and a real-device test checklist. A reference verification server is in the repository (`server/`).
