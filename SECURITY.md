# Security policy

Compliance Kit is security and privacy tooling, so vulnerabilities in it can expose the users of apps that rely on it. Please report them privately.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: **Security > Report a vulnerability** on [the repository](https://github.com/Ahmadhussain0335/compliance_kit/security/advisories/new). Do not open a public issue, pull request or discussion for a vulnerability.

Please include:

- the affected package and version (or commit);
- what an attacker can achieve and under which conditions;
- a minimal reproduction, using only fake data;
- any suggested fix.

You will get an acknowledgement within 7 days. Fixes are released as patch versions, and the advisory is published once a fix is available. Reporters are credited unless they prefer otherwise.

## What counts as a vulnerability

- A redaction bypass in `compliance_logger`: personal data or secrets reaching a sink unmasked, or the logger throwing raw data into the app.
- Personal data, tokens or keys appearing in audit event metadata.
- Consent being treated as granted when it was not, or withdrawal not taking effect.
- Export including data it should not, or deletion reporting success when data was kept.
- `compliance_integrity` reporting a token it did not obtain, or leaking tokens or key ids.
- A verification bypass in the reference server (`server/`): a forged, replayed or other-app token being accepted.

Denial-of-service issues in the reference server are welcome too, but note that it is a reference example and documents the hardening needed for production.

## Supported versions

| Version | Supported |
|---|---|
| 0.1.x | Yes |

## Scope limits

Compliance Kit helps implement controls; it does not make an application compliant. Misconfiguration in an app (for example logging with `print`, or starting an analytics SDK before consent) is outside the scope of this policy, but documentation improvements are welcome.
