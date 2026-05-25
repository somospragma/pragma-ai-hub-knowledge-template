---
name: flutter-certificate-pinning
description: >
  Implements certificate pinning in Flutter to prevent MITM attacks: public key (SPKI) SHA-256 pinning via Dio interceptor, Android Network Security Config, iOS ATS, pin rotation strategy, and backend coordination guide. Covers OWASP MASVS-NETWORK-2 compliance (L2 requirement). Use this skill for banking, healthcare, fintech, or any app handling sensitive data that requires defense against network interception.
commands:
  - setup-certificate-pinning
inputs:
  - name: action
    description: Action to perform (implement, rotate, audit). "implement" generates the full pinning setup (Dio interceptor, Android config, iOS config), "rotate" guides through the pin rotation workflow, "audit" checks existing pinning for single-pin vulnerability, missing backup, or incorrect strategy.
    required: true
  - name: target
    description: Path to the network/security directory or project root (e.g. lib/core/network/ for implement, . for audit).
    required: true
  - name: domain
    description: Server domain to pin (e.g. api.yourapp.com). Required when action is "implement" to extract the SPKI hash.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Certificate Pinning

See the reference files for complete patterns and code examples.

**Certificate pinning prevents MITM attacks by ensuring the app only trusts
specific cryptographic keys — not any certificate signed by a trusted CA.**

## OWASP MASVS-NETWORK Requirements

| Control | Requirement | Level |
|---|---|---|
| **MASVS-NETWORK-1** | All network traffic uses TLS 1.2+ | L1 |
| **MASVS-NETWORK-2** | Certificate pinning implemented for sensitive endpoints | L2 |
| **MASVS-NETWORK-2** | Pinning failure results in connection rejection — not fallback | L2 |
| **MASVS-NETWORK-2** | Backup pins included to enable rotation without app update | L2 |

---

## Pinning Strategy — Public Key (SPKI) vs Leaf Certificate

| Strategy | Survives cert rotation | Recommended |
|---|---|---|
| **Leaf certificate** | ❌ No — breaks on every renewal | ❌ Avoid |
| **Intermediate CA public key** | ✅ Yes — stable across renewals | ✅ Preferred |
| **Root CA public key** | ✅ Yes — most stable | ⚠️ Too broad |
| **Subject Public Key Info (SPKI)** | ✅ Yes — pins the key, not the cert | ✅ Best practice |

**Always pin the intermediate CA's public key (SPKI SHA-256), not the leaf certificate.**
The leaf certificate changes on every renewal. The public key stays stable.

---

## Always Include a Backup Pin

```
❌ Single pin — app breaks if server rotates before app update
✅ Current pin + backup pin — rotation without app update
```

The backup pin is the SPKI hash of the **next** certificate/key pair,
generated before the rotation happens.

---

## Core Implementation — Quick Reference

### Extract SPKI SHA-256 (run on your server)
```bash
# From a live server
openssl s_client -connect api.yourapp.com:443 -servername api.yourapp.com 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

### Dio interceptor (Flutter)
```dart
// In SecurityContext or BadCertificateCallback — validate SPKI hash
final expectedPins = {
  'sha256/CURRENT_SPKI_HASH_BASE64==',  // current
  'sha256/BACKUP_SPKI_HASH_BASE64==',   // backup — for rotation
};
```

### Android Network Security Config
```xml
<pin-set expiration="2027-01-01">
    <pin digest="SHA-256">CURRENT_SPKI_HASH_BASE64==</pin>
    <pin digest="SHA-256">BACKUP_SPKI_HASH_BASE64==</pin>
</pin-set>
```

---

## Rotation Workflow (Mobile + Backend)

```
Step 1 — Generate new key pair on server (do NOT deploy yet)
Step 2 — Extract SPKI hash of new key pair
Step 3 — Add new hash as backup pin in app → release app update
Step 4 — Wait for app update adoption (≥ 90% of users)
Step 5 — Deploy new certificate on server
Step 6 — Remove old pin from app → release app update
```

**Never rotate the server certificate before the backup pin is in the app.**

---

## Quick Wins Checklist

- [ ] SPKI SHA-256 used — not leaf certificate fingerprint
- [ ] Current pin + backup pin always present
- [ ] Pinning failure rejects connection — no fallback to system trust store
- [ ] Android Network Security Config configured
- [ ] iOS ATS configured (no `NSAllowsArbitraryLoads`)
- [ ] Pin expiration date set in Android config (forces rotation awareness)
- [ ] Rotation runbook documented and shared with backend team
- [ ] Debug/staging builds use separate pinning config (not production pins)
- [ ] Pinning bypass tested with Frida/objection in QA

## Reference Files

- `references/flutter_implementation.md` — Dio interceptor, SecurityContext, pin extraction, DI integration
- `references/platform_config.md` — Android Network Security Config, iOS ATS, debug overrides
- `references/rotation_and_backend.md` — rotation runbook, backend coordination, SPKI extraction commands, testing
