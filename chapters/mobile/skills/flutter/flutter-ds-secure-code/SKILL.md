---
name: flutter-ds-secure-code
description: >
  Security rules for Design System code based on OWASP Mobile Application
  Security and Pragma standards. Use when auditing code security, validating
  inputs, reviewing dependencies, or checking for data exposure risks.
commands:
  - audit-ds-security
inputs:
  - name: action
    description: Action to perform (audit, fix). "audit" checks DS component code for security violations (unauthorized imports, force unwraps, print statements, missing input validation), "fix" applies security fixes to identified issues.
    required: true
  - name: target
    description: Path to the DS component file or package directory to audit (e.g. lib/ui_system/ for full audit, lib/ui_system/molecules/text_field/ for specific component).
    required: true
metadata:
  author: pragma-ds
  version: "1.1"
  domain: flutter-design-system
---

# Secure Code

> **Scope**: Este skill cubre reglas de seguridad **específicas para componentes del Design System** (validación de inputs en widgets, exposición de datos en UI, dependencias del DS). Para auditoría OWASP completa (M1-M10), almacenamiento seguro y cifrado → ver skills `flutter-owasp-mobile-top10`, `flutter-secure-storage`, `flutter-data-encryption`.

## Pragma Security Principles

1. Validate and sanitize all user input and external data
2. Protect credentials and sensitive data
3. Use secure encryption for data at rest and in transit
4. Secure communication (HTTPS/TLS)
5. Keep dependencies updated
6. Handle errors without exposing internal information

## DS-Specific Rules

### Input Validation

```dart
// ✅ CORRECT — Validate before rendering
class {{DS_PREFIX}}TextField extends StatelessWidget {
  final String? Function(String?)? validator;
  final int? maxLength;

  Widget build(BuildContext context) {
    return TextFormField(
      validator: validator,
      maxLength: maxLength,
      inputFormatters: [
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
    );
  }
}
```

### No Sensitive Data Exposure

```dart
// ✅ Obfuscate sensitive data
String get _displayText => isMasked ? '•' * text.length : text;

// ❌ NEVER log user data
print('User input: $sensitiveData');
```

### Authorized Dependencies Only

```dart
// ✅ DS may only depend on:
//   - flutter/material.dart
//   - own DS package
//   - alchemist (dev only)
//   - widgetbook (dev only)
//   - flutter_test (dev only)

// ❌ FORBIDDEN
import 'package:http/http.dart';             // DS doesn't make requests
import 'package:shared_preferences/...';      // DS doesn't persist data
```

### Safe Error Handling

```dart
// ✅ Safe visual fallback
try { return _buildContent(context); }
catch (e) { return _buildError(context); }

// ❌ NEVER expose stack traces
Text(error.toString())
```

### Null Safety

```dart
// ✅ Safe call
onPressed?.call();

// ❌ NEVER force unwrap unnecessarily
onPressed!();
```

## Checklist

- [ ] No `print()` in production code
- [ ] No sensitive data in logs or error messages
- [ ] No unauthorized dependencies
- [ ] Text inputs with `maxLength` and/or `inputFormatters`
- [ ] Nullable callbacks with safe call (`?.call()`)
- [ ] No unnecessary force unwrap (`!`)
- [ ] Error handling with visual fallback
- [ ] No hardcoded URLs, API keys, or credentials

## OWASP Mobile Top 10 (Applicable)

| ID | Threat | DS Mitigation |
|----|--------|--------------|
| M7 | Code Quality | SOLID, strict linting, no dead code |
| M8 | Code Tampering | Obfuscation in release builds |
| M9 | Reverse Engineering | No sensitive business logic in widgets |
