# Rotation Runbook & Backend Coordination

Certificate pinning only works if the rotation process is coordinated between
the mobile team and the backend/infrastructure team. A missed step causes
a production outage for all pinned app versions.

---

## Why Rotation Matters

```
Without backup pin:
  Server rotates cert → All pinned app versions break → Production outage

With backup pin + proper rotation:
  1. Backup pin deployed in app → users update
  2. Server rotates cert → backup pin matches → no outage
  3. Old pin removed from app → next release
```

---

## Rotation Runbook — Step by Step

### Phase 1 — Prepare (Mobile + Backend)

```
[ Backend ]
1. Generate new private key and CSR on the server
   (Do NOT deploy yet — just generate)

2. Obtain new certificate from CA using the new CSR

3. Extract SPKI SHA-256 hash of the NEW key pair:
   openssl req -in new.csr -pubkey -noout \
     | openssl pkey -pubin -outform DER \
     | openssl dgst -sha256 -binary \
     | openssl enc -base64
   → Share this hash with the mobile team

[ Mobile ]
4. Add the new hash as the BACKUP pin in PinConfig
   (Keep the current pin — both must be present)

5. Update Android Network Security Config:
   - Keep current <pin> entry
   - Add new <pin> entry as backup
   - Update expiration date

6. Release app update with both pins
```

### Phase 2 — Wait for Adoption

```
[ Mobile ]
7. Monitor app version distribution in Play Console / App Store Connect
   Target: ≥ 90% of active users on the new version

   Typical timeline:
   - Play Store: 1–2 weeks for 90% adoption (staged rollout)
   - App Store: 2–4 weeks for 90% adoption

   ⚠️ Do NOT proceed to Phase 3 until adoption target is met
   Users on old versions (without backup pin) will break after server rotation
```

### Phase 3 — Rotate Server Certificate

```
[ Backend ]
8. Deploy new certificate on the server
   The backup pin in the app now matches the new certificate

9. Verify the new certificate is served correctly:
   openssl s_client -connect api.yourapp.com:443 -servername api.yourapp.com \
     | openssl x509 -noout -dates -subject -issuer

10. Monitor error rates — a spike indicates users on old app versions

[ Mobile ]
11. Verify pinning still works with the new certificate:
    Run the app → make API calls → confirm no certificate errors
```

### Phase 4 — Cleanup

```
[ Mobile ]
12. Remove the OLD pin from PinConfig (now only the new pin remains)
13. Add a new BACKUP pin for the NEXT rotation (repeat the cycle)
14. Release app update

[ Backend ]
15. Revoke the old certificate if needed
16. Document the new certificate expiry date
17. Schedule the next rotation reminder (90 days before expiry)
```

---

## SPKI Hash Extraction Commands

### From a live server

```bash
# Extract SPKI SHA-256 from a live server
openssl s_client -connect api.yourapp.com:443 -servername api.yourapp.com 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

### From a certificate file (.pem or .crt)

```bash
# From a PEM certificate file
openssl x509 -in certificate.pem -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

### From a CSR (for backup pin — before deployment)

```bash
# From a CSR — use this to get the backup pin BEFORE deploying the new cert
openssl req -in new_request.csr -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

### Verify the hash matches what's in the app

```bash
# Run this and compare with PinConfig.productionPins
LIVE_HASH=$(openssl s_client -connect api.yourapp.com:443 -servername api.yourapp.com 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64)

echo "Live server SPKI hash: sha256/$LIVE_HASH"
echo "Compare with your PinConfig.productionPins"
```

---

## Backend Responsibilities

### Certificate lifecycle management

```
┌─────────────────────────────────────────────────────────────┐
│  Certificate Lifecycle                                       │
│                                                              │
│  Issue date ──────────────────────────── Expiry date        │
│                                                              │
│  ← 90 days before expiry: start rotation process            │
│  ← 60 days before expiry: backup pin must be in app         │
│  ← 30 days before expiry: server rotation must be complete  │
│  ← 14 days before expiry: CRITICAL — escalate if not done   │
└─────────────────────────────────────────────────────────────┘
```

### Backend checklist for each rotation

- [ ] New private key generated (never reuse old keys)
- [ ] CSR generated from new key
- [ ] New certificate obtained from CA
- [ ] SPKI hash of new key extracted and shared with mobile team
- [ ] Deployment scheduled AFTER mobile team confirms backup pin adoption
- [ ] Rollback plan documented (keep old cert available for 24h after rotation)
- [ ] Monitoring alerts configured for certificate errors post-rotation
- [ ] Old certificate revoked after successful rotation

### Nginx configuration example

```nginx
# /etc/nginx/sites-available/api.yourapp.com
server {
    listen 443 ssl http2;
    server_name api.yourapp.com;

    # Current certificate
    ssl_certificate /etc/ssl/certs/api.yourapp.com.crt;
    ssl_certificate_key /etc/ssl/private/api.yourapp.com.key;

    # TLS hardening — required for MASVS-NETWORK-1
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # HSTS — forces HTTPS for 1 year
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Disable weak headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
}
```

---

## Monitoring & Alerting

### What to monitor

```
1. Certificate expiry — alert 90 days before expiry
2. Pinning failure rate — spike = active MITM or missed rotation
3. App version distribution — ensure backup pin adoption before rotation
4. TLS handshake errors — may indicate pinning issues
```

### Certificate expiry monitoring (bash script for CI/CD)

```bash
#!/bin/bash
# check_cert_expiry.sh — run in CI/CD pipeline daily

DOMAIN="api.yourapp.com"
WARN_DAYS=90

EXPIRY=$(echo | openssl s_client -connect $DOMAIN:443 -servername $DOMAIN 2>/dev/null \
  | openssl x509 -noout -enddate \
  | cut -d= -f2)

EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s)
NOW_EPOCH=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

echo "Certificate for $DOMAIN expires in $DAYS_LEFT days ($EXPIRY)"

if [ $DAYS_LEFT -lt $WARN_DAYS ]; then
  echo "⚠️  WARNING: Certificate expires in $DAYS_LEFT days — start rotation process"
  exit 1
fi

echo "✅ Certificate is valid for $DAYS_LEFT more days"
```

---

## Security Considerations

### Pinning bypass risks

Certificate pinning can be bypassed on rooted/jailbroken devices using tools
like Frida, objection, or SSL Kill Switch. This is a known limitation.

```
Mitigation layers (defense in depth):
1. Certificate pinning — prevents casual MITM on unrooted devices
2. Root/jailbreak detection — detect compromised devices (see flutter-root-detection skill)
3. Code obfuscation — makes bypass harder (--obfuscate --split-debug-info)
4. Runtime integrity checks — detect Frida/hook injection
5. Backend anomaly detection — flag unusual request patterns
```

### What pinning does NOT protect against

```
❌ Rooted/jailbroken devices with bypass tools
❌ Compromised device (malware with root access)
❌ Reverse engineering of the app binary
❌ Server-side vulnerabilities
✅ MITM on untrusted networks (coffee shop, hotel WiFi)
✅ Rogue CA certificates installed by enterprise MDM
✅ Compromised CA (if pinning intermediate, not root)
```

### MASVS-NETWORK-2 compliance checklist

- [ ] Pinning implemented for all sensitive API endpoints
- [ ] Pinning failure rejects connection — no fallback to system trust store
- [ ] Backup pin present to enable rotation
- [ ] Pin expiration date set in Android Network Security Config
- [ ] Pinning tested with mitmproxy/Charles Proxy (connection must fail)
- [ ] Pinning bypass tested with Frida/objection (document findings)
- [ ] Rotation runbook documented and tested
- [ ] Backend team has the runbook and understands the coordination requirement
