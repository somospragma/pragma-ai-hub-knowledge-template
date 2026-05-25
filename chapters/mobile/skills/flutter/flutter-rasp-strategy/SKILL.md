---
name: flutter-rasp-strategy
description: > 
  Implements Runtime Application Self-Protection (RASP) in Flutter using freeRASP (Talsec) as the primary provider: root/jailbreak detection, emulator detection, hook/Frida detection, tamper detection, and untrusted installation detection. Uses a Strategy + Adapter pattern so the RASP provider can be swapped without touching domain or presentation layers. Covers OWASP MASVS-RESILIENCE requirements (R category).
commands:
  - setup-rasp
inputs:
  - name: action
    description: Action to perform (implement, audit, migrate). "implement" generates the full RASP setup with provider pattern, "audit" checks existing RASP configuration for missing threat responses or misconfigurations, "migrate" swaps the underlying RASP provider (e.g. freeRASP to commercial).
    required: true
  - name: target
    description: Path to the core/security directory or feature where RASP will be integrated (e.g. lib/core/security/).
    required: true
  - name: provider
    description: RASP provider to use (freerasp, custom). Defaults to freerasp.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# RASP Strategy

See the reference files for complete patterns and code examples.

**RASP = the app monitors its own runtime environment and reacts to threats.**

## OWASP MASVS-RESILIENCE Requirements

RASP covers the **R (Resilience)** category — defense against reverse engineering
and tampering. These are not required for L1/L2 but are mandatory for high-security
apps (banking, fintech, healthcare).

| Control | Requirement |
|---|---|
| **MASVS-RESILIENCE-1** | App detects and responds to rooted/jailbroken devices |
| **MASVS-RESILIENCE-2** | App prevents debugging and detects debugger attachment |
| **MASVS-RESILIENCE-3** | App detects and responds to tampering of executables and data |
| **MASVS-RESILIENCE-4** | App detects reverse engineering tools (Frida, Xposed, etc.) |

---

## Primary Provider — freeRASP (Talsec)

```yaml
dependencies:
  freerasp: ^6.11.0
```

freeRASP detects:
- Root (Magisk, su, SuperSU) / Jailbreak (unc0ver, checkra1n, Dopamine)
- Hooking frameworks (Frida, Shadow, Xposed)
- Emulator / simulator
- App tampering (signature mismatch)
- Untrusted installation source
- Debugger attachment
- Malware on device (Android)
- Secure hardware unavailability

---

## Provider Strategy Pattern

If the project needs to swap RASP providers (freeRASP → commercial RASP → custom),
use the Strategy + Adapter pattern. Domain and presentation layers only know
`RaspProvider` — never a specific SDK.

```
Domain (RaspProvider interface)
  ↓ abstract interface class
Data (RaspProviderAdapter)
  ├── FreeRaspAdapter      implements RaspProvider  ← primary (freeRASP)
  ├── CommercialRaspAdapter implements RaspProvider  ← e.g. future commercial
  └── MockRaspAdapter      implements RaspProvider  ← tests
DI
  └── bind RaspProvider → FreeRaspAdapter  ← change to swap
```

---

## Threat Response Strategy

**Never silently ignore threats.** Define a response per threat level:

| Threat | Recommended response |
|---|---|
| Root / Jailbreak | Block app — show warning, prevent sensitive operations |
| Hook / Frida | Block app — active attack in progress |
| Tamper / Signature mismatch | Block app — binary has been modified |
| Emulator | Block in production, allow in debug/staging |
| Untrusted installation | Warn user — redirect to official store |
| Debugger | Block in production |
| Malware detected | Warn user — list suspicious apps |

---

## Quick Wins Checklist

- [ ] `isProd: true` in release builds — `isProd: false` in debug only
- [ ] `expectedPackageName` matches `applicationId` in `build.gradle`
- [ ] `expectedSigningCertificateHashes` contains Play Store signing cert hash
- [ ] `bundleIds` matches iOS bundle ID
- [ ] `teamId` matches Apple Developer Team ID
- [ ] Root/jailbreak → app blocked (not just warned)
- [ ] Hook/Frida → app blocked immediately
- [ ] Emulator → blocked in production, allowed in debug
- [ ] Threat callbacks dispatch to BLoC — never call `exit()` directly from callback
- [ ] `RaspProvider` interface used — not freeRASP SDK directly in BLoC/domain

## Reference Files

- `references/freerasp_implementation.md` — freeRASP setup, TalsecConfig, ThreatCallback, BLoC integration, signing cert extraction
- `references/rasp_provider_pattern.md` — Strategy + Adapter pattern, RaspProvider interface, FreeRaspAdapter, MockRaspAdapter, DI binding
