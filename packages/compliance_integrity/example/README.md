# compliance_integrity example

Requests a Play Integrity token (Android) or an App Attest attestation/assertion (iOS) and shows the result type and the recorded audit events.

The example generates the request hash locally to stay self-contained. A real app must get it from its server and send the token back to that server for verification; see `server/` in the repository root.

```sh
# Android (device with Google Play):
flutter run --dart-define=CLOUD_PROJECT_NUMBER=<your Google Cloud project number>

# iOS (real device; the simulator reports "unsupported"):
flutter run
```

On iOS, set your development team and enable the App Attest capability for the Runner target before running on a device.
