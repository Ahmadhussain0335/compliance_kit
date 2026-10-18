# compliance_integrity guide

## Flow

```
App                                   Your server                      Google / Apple
 | POST /challenge  ------------------> issue single-use challenge
 | <-------------------------------- challenge
 | requestToken(challenge)
 |   Android: Play Integrity token  ------------------------------------> (Play)
 |   iOS: attestation or assertion   -----------------------------------> (Apple, first time)
 | POST /verify {token, challenge} --> consume challenge
 |                                     Android: decodeIntegrityToken ----> Google API
 |                                     iOS: verify CBOR, chain, nonce
 | <-------------------------------- allow / deny / step-up
```

The reference server in [`server/`](../server) implements the right-hand side.

## Server policy

Decide per action what you require, for example:

| Action | Android | iOS |
|---|---|---|
| Sign-in | `MEETS_DEVICE_INTEGRITY`, `PLAY_RECOGNIZED` | valid assertion |
| Payment | plus `LICENSED`, maybe `MEETS_STRONG_INTEGRITY` | valid assertion, counter increased |
| Read-only content | none, log only | none, log only |

Always have a path for devices that cannot attest (no Google Play services, Macs, old devices): extra verification, rate limits or reduced functionality, not a silent lockout.

## Rollout

1. Ship the client, verify on the server, but only log the result.
2. Watch failure rates per platform, app version and OS version.
3. Enforce for the riskiest actions first.
4. Keep Play quota (10,000 requests/day by default) and Apple's attestation rate guidance in mind; prepare tokens ahead (`prepare()`) and do not request one for every API call.

## Platform setup

See the "Setup" section of the [package README](../packages/compliance_integrity/README.md) for Google Play Console, Google Cloud and Apple Developer steps, and the manual device test checklist.
