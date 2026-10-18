## 0.1.0

- Initial release.
- `Integrity` with `isSupported`, `prepare`, `requestToken` and `reset`.
- Android: Play Integrity standard requests (library 1.6.0), provider caching and automatic re-preparation, no Firebase.
- iOS: App Attest key generation, attestation and assertions; key id stored in the Keychain (this device only); automatic re-attestation when a key is rejected.
- Typed results: success, unsupported, Play services missing, network error, rate limited, configuration error, platform error. No method throws.
- Pigeon-generated platform channel.
- `integrity_check_passed` / `integrity_check_failed` audit events with the result type only.
