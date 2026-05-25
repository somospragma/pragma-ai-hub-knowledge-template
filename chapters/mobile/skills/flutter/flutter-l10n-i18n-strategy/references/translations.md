# Translations — gen-l10n (Default) and slang (Alternative)

## Option A: Official gen-l10n + flutter_localizations (Default)

The Flutter team's official approach. Uses ARB files and generates type-safe
Dart code via `flutter gen-l10n`. No additional packages needed beyond the SDK.

### Setup

```yaml
# pubspec.yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.2

flutter:
  generate: true   # ✅ enables flutter gen-l10n
```

### l10n.yaml Configuration

```yaml
# l10n.yaml (project root)
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
use-escaping: true
preferred-supported-locales:
  - en
  - es
  - ar
  - pt_BR
```

### ARB Files

```
lib/
└── l10n/
    ├── app_en.arb      ← template (base locale, required)
    ├── app_es.arb
    ├── app_ar.arb
    └── app_pt_BR.arb
```

### app_en.arb — Template file

```json
{
  "@@locale": "en",

  "commonOk": "OK",
  "@commonOk": { "description": "Generic OK button label" },

  "commonCancel": "Cancel",
  "@commonCancel": {},

  "commonLoading": "Loading...",
  "@commonLoading": {},

  "commonErrorNetwork": "No internet connection. Please try again.",
  "@commonErrorNetwork": {},

  "commonErrorUnknown": "Something went wrong.",
  "@commonErrorUnknown": {},

  "authLoginTitle": "Sign In",
  "@authLoginTitle": {},

  "authLoginEmailLabel": "Email address",
  "@authLoginEmailLabel": {},

  "authLoginPasswordLabel": "Password",
  "@authLoginPasswordLabel": {},

  "authLoginSubmitButton": "Sign In",
  "@authLoginSubmitButton": {},

  "authLoginForgotPassword": "Forgot password?",
  "@authLoginForgotPassword": {},

  "authLoginNoAccount": "Don't have an account? {action}",
  "@authLoginNoAccount": {
    "placeholders": { "action": { "type": "String" } }
  },

  "productDetailPrice": "Price: {price}",
  "@productDetailPrice": {
    "placeholders": { "price": { "type": "String" } }
  },

  "productDetailAddToCart": "Add to Cart",
  "@productDetailAddToCart": {},

  "productDetailOutOfStock": "Out of Stock",
  "@productDetailOutOfStock": {},

  "productListItemCount": "{count, plural, =0{No items} =1{1 item} other{{count} items}}",
  "@productListItemCount": {
    "description": "Number of items in a list",
    "placeholders": { "count": { "type": "int" } }
  },

  "cartTitle": "Your Cart",
  "@cartTitle": {},

  "cartEmpty": "Your cart is empty",
  "@cartEmpty": {},

  "cartCheckoutButton": "Checkout ({count})",
  "@cartCheckoutButton": {
    "placeholders": { "count": { "type": "int" } }
  },

  "cartItemRemoved": "{name} removed from cart",
  "@cartItemRemoved": {
    "placeholders": { "name": { "type": "String" } }
  },

  "greetingByGender": "{gender, select, male{Hello, Mr. {name}!} female{Hello, Ms. {name}!} other{Hello, {name}!}}",
  "@greetingByGender": {
    "placeholders": {
      "gender": { "type": "String" },
      "name": { "type": "String" }
    }
  }
}
```

### app_es.arb — Spanish

```json
{
  "@@locale": "es",
  "commonOk": "Aceptar",
  "commonCancel": "Cancelar",
  "commonLoading": "Cargando...",
  "commonErrorNetwork": "Sin conexión a internet. Inténtalo de nuevo.",
  "commonErrorUnknown": "Algo salió mal.",
  "authLoginTitle": "Iniciar sesión",
  "authLoginEmailLabel": "Correo electrónico",
  "authLoginPasswordLabel": "Contraseña",
  "authLoginSubmitButton": "Iniciar sesión",
  "authLoginForgotPassword": "¿Olvidaste tu contraseña?",
  "authLoginNoAccount": "¿No tienes cuenta? {action}",
  "productDetailPrice": "Precio: {price}",
  "productDetailAddToCart": "Agregar al carrito",
  "productDetailOutOfStock": "Sin stock",
  "productListItemCount": "{count, plural, =0{Sin artículos} =1{1 artículo} other{{count} artículos}}",
  "cartTitle": "Tu carrito",
  "cartEmpty": "Tu carrito está vacío",
  "cartCheckoutButton": "Pagar ({count})",
  "cartItemRemoved": "{name} eliminado del carrito",
  "greetingByGender": "{gender, select, male{¡Hola, Sr. {name}!} female{¡Hola, Sra. {name}!} other{¡Hola, {name}!}}"
}
```

### Code Generation

```bash
# Generate — runs automatically with flutter run / flutter build
flutter gen-l10n

# Validate ARB files in CI
flutter gen-l10n && echo "✅ All translations valid"
```

### App Integration

```dart
// lib/main.dart
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      localizationsDelegates: const [
        AppLocalizations.delegate,                  // ✅ generated delegate
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: _userSelectedLocale,                  // optional override
      routerConfig: GetIt.instance<AppRouter>().router,
    );
  }
}
```

### BuildContext Extension (shorter access)

```dart
// lib/core/l10n/app_localizations_extension.dart
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
```

### Usage in Widgets

```dart
// ✅ Type-safe — compile error if key doesn't exist
Text(context.l10n.authLoginTitle)
Text(context.l10n.commonErrorNetwork)

// ✅ With parameters
Text(context.l10n.productDetailPrice('\$9.99'))
Text(context.l10n.cartCheckoutButton(cart.itemCount))
Text(context.l10n.cartItemRemoved(product.name))
Text(context.l10n.authLoginNoAccount('Sign up'))

// ✅ Plurals — ICU selects the right form automatically
Text(context.l10n.productListItemCount(products.length))

// ✅ Gender select
Text(context.l10n.greetingByGender(user.gender, user.displayName))
```

### Dynamic Locale Switching

```dart
// lib/core/l10n/locale_service.dart
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

@lazySingleton
class LocaleService {
  static const _key = 'app_locale';

  Future<void> setLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.toLanguageTag());
  }

  Future<Locale?> getSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final tag = prefs.getString(_key);
    if (tag == null) return null;
    final parts = tag.split('-');
    return parts.length > 1
        ? Locale(parts[0], parts[1])
        : Locale(parts[0]);
  }

  List<Locale> get supportedLocales => AppLocalizations.supportedLocales;
}
```

### ICU Message Syntax Reference

```
Simple string:
  "Hello World"

With parameter:
  "Hello, {name}!"

Plural:
  "{count, plural, =0{No items} =1{One item} other{{count} items}}"

Gender:
  "{gender, select, male{Mr.} female{Ms.} other{Mx.}} {name}"

Select (enum-like):
  "{status, select, active{Active} inactive{Inactive} other{Unknown}}"

Nested plural + parameter:
  "{count, plural, =1{You have {count} message} other{You have {count} messages}}"
```

### ARB Key Naming Convention

```
✅ Hierarchical camelCase matching the UI structure:
  authLoginTitle
  authLoginEmailLabel
  productDetailAddToCart
  commonErrorNetwork

❌ Flat or ambiguous:
  title
  error
  btn1
```

### CI — Missing Translation Check

```yaml
# .github/workflows/l10n_check.yml
name: L10n Check
on: [pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.x'
      - name: Validate ARB translations
        run: flutter gen-l10n && echo "✅ All translations valid"
```

---

## Option B: slang (Alternative — Type-Safe, JSON/YAML)

Use slang when you need JSON/YAML format, Flutter-independent translations
(shared Dart packages), or zero runtime parsing.

### Setup

```yaml
dependencies:
  slang: ^4.14.0
  slang_flutter: ^4.14.0

dev_dependencies:
  slang_build_runner: ^4.14.0
  build_runner: ^2.14.1
```

### slang.yaml

```yaml
# slang.yaml (project root)
base_locale: en
fallback_strategy: base_locale
input_directory: lib/l10n
input_file_pattern: .i18n.json
output_directory: lib/l10n
output_file_name: translations.g.dart
flutter_integration: true
render_flat_map: true
```

### en.i18n.json — Base locale (JSON format)

```json
{
  "common": {
    "ok": "OK",
    "cancel": "Cancel",
    "error": {
      "network": "No internet connection. Please try again."
    }
  },
  "auth": {
    "login": {
      "title": "Sign In",
      "submit_button": "Sign In"
    }
  },
  "product": {
    "list": {
      "item_count": {
        "zero": "No items",
        "one": "{count} item",
        "other": "{count} items"
      },
      "@item_count": { "param": "count" }
    }
  }
}
```

### Code Generation

```bash
dart run build_runner build --delete-conflicting-outputs
dart run slang analyze --exit-code 1   # CI: fail on missing keys
```

### App Integration

```dart
// Wrap with TranslationProvider
TranslationProvider(
  child: MaterialApp.router(
    locale: TranslationProvider.of(context).flutterLocale,
    supportedLocales: AppLocaleUtils.supportedLocales,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: GetIt.instance<AppRouter>().router,
  ),
)
```

### Usage

```dart
// Type-safe dot-notation access
Text(context.t.auth.login.title)
Text(context.t.product.list.itemCount(count: products.length))
```

Type-safe translations generated from JSON/YAML/ARB/CSV files.
Zero runtime parsing — translations are native Dart method calls.

### Setup

```yaml
dependencies:
  slang: ^4.14.0
  slang_flutter: ^4.14.0

dev_dependencies:
  slang_build_runner: ^4.14.0
  build_runner: ^2.14.1
```

### slang.yaml

```yaml
# slang.yaml (project root)
base_locale: en
fallback_strategy: base_locale     # use base locale for missing keys
input_directory: lib/l10n
input_file_pattern: .i18n.json
output_directory: lib/l10n
output_file_name: translations.g.dart
flutter_integration: true          # enables context.t
render_flat_map: true              # enables missing key detection
```

### Translation Files

```
lib/
└── l10n/
    ├── en.i18n.json          ← base locale (required)
    ├── es.i18n.json
    ├── ar.i18n.json          ← RTL
    ├── pt_BR.i18n.json       ← regional variant
    └── translations.g.dart   ← generated, do not edit
```

### en.i18n.json — Base locale

```json
{
  "common": {
    "ok": "OK",
    "cancel": "Cancel",
    "loading": "Loading...",
    "retry": "Try again",
    "error": {
      "network": "No internet connection. Please try again.",
      "unknown": "Something went wrong.",
      "not_found": "The requested resource was not found."
    }
  },
  "auth": {
    "login": {
      "title": "Sign In",
      "email_label": "Email address",
      "password_label": "Password",
      "submit_button": "Sign In",
      "forgot_password": "Forgot password?",
      "no_account": "Don't have an account? {action}",
      "@no_account": { "param": "action" }
    },
    "logout": {
      "confirm_title": "Sign Out",
      "confirm_message": "Are you sure you want to sign out?"
    }
  },
  "product": {
    "detail": {
      "add_to_cart": "Add to Cart",
      "out_of_stock": "Out of Stock",
      "price": "Price: {price}",
      "@price": { "param": "price" }
    },
    "list": {
      "item_count": {
        "zero": "No items",
        "one": "{count} item",
        "other": "{count} items"
      },
      "@item_count": { "param": "count" }
    }
  },
  "cart": {
    "title": "Your Cart",
    "empty": "Your cart is empty",
    "checkout_button": "Checkout ({count})",
    "@checkout_button": { "param": "count" },
    "item_removed": "{name} removed from cart",
    "@item_removed": { "param": "name" }
  },
  "greeting": {
    "by_gender": {
      "male": "Hello, Mr. {name}!",
      "female": "Hello, Ms. {name}!",
      "other": "Hello, {name}!"
    },
    "@by_gender": { "param": "name" }
  }
}
```

### es.i18n.json — Spanish

```json
{
  "common": {
    "ok": "Aceptar",
    "cancel": "Cancelar",
    "loading": "Cargando...",
    "retry": "Intentar de nuevo",
    "error": {
      "network": "Sin conexión a internet. Inténtalo de nuevo.",
      "unknown": "Algo salió mal.",
      "not_found": "El recurso solicitado no fue encontrado."
    }
  },
  "auth": {
    "login": {
      "title": "Iniciar sesión",
      "email_label": "Correo electrónico",
      "password_label": "Contraseña",
      "submit_button": "Iniciar sesión",
      "forgot_password": "¿Olvidaste tu contraseña?",
      "no_account": "¿No tienes cuenta? {action}"
    }
  },
  "product": {
    "detail": {
      "add_to_cart": "Agregar al carrito",
      "out_of_stock": "Sin stock",
      "price": "Precio: {price}"
    },
    "list": {
      "item_count": {
        "zero": "Sin artículos",
        "one": "{count} artículo",
        "other": "{count} artículos"
      }
    }
  },
  "cart": {
    "title": "Tu carrito",
    "empty": "Tu carrito está vacío",
    "checkout_button": "Pagar ({count})",
    "item_removed": "{name} eliminado del carrito"
  },
  "greeting": {
    "by_gender": {
      "male": "¡Hola, Sr. {name}!",
      "female": "¡Hola, Sra. {name}!",
      "other": "¡Hola, {name}!"
    }
  }
}
```

### Code Generation

```bash
# Generate once
dart run build_runner build --delete-conflicting-outputs

# Watch mode during development
dart run build_runner watch --delete-conflicting-outputs

# Detect missing translations
dart run slang analyze

# Fail CI if any key is missing
dart run slang analyze --exit-code 1
```

### App Integration

```dart
// lib/main.dart
import 'package:slang_flutter/slang_flutter.dart';
import 'l10n/translations.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore saved locale or detect from device
  final savedLocale = await _loadSavedLocale();
  LocaleSettings.setLocale(savedLocale ?? AppLocaleUtils.findDeviceLocale());

  await configureDependencies();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return TranslationProvider(          // ✅ required for context.t
      child: Builder(
        builder: (context) => MaterialApp.router(
          locale: TranslationProvider.of(context).flutterLocale,
          supportedLocales: AppLocaleUtils.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: GetIt.instance<AppRouter>().router,
        ),
      ),
    );
  }
}
```

### Usage in Widgets

```dart
// ✅ Type-safe — compile error if key doesn't exist
Text(context.t.auth.login.title)
Text(context.t.common.error.network)

// ✅ With parameters
Text(context.t.product.detail.price(price: '\$9.99'))
Text(context.t.cart.checkoutButton(count: cart.itemCount))
Text(context.t.cart.itemRemoved(name: product.name))

// ✅ Plurals — automatically selects zero/one/other
Text(context.t.product.list.itemCount(count: products.length))

// ✅ Gender select
Text(context.t.greeting.byGender(
  gender: user.gender,  // 'male' | 'female' | 'other'
  name: user.displayName,
))

// ✅ Without context (in BLoC, services, etc.)
final t = AppLocale.en.build();
final message = t.common.error.network;
```

### Dynamic Locale Switching

```dart
// lib/core/l10n/locale_service.dart
import 'package:slang_flutter/slang_flutter.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

@lazySingleton
class LocaleService {
  static const _key = 'app_locale';

  Future<void> setLocale(AppLocale locale) async {
    LocaleSettings.setLocale(locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, locale.languageTag);
  }

  Future<AppLocale> getSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final tag = prefs.getString(_key);
    if (tag == null) return AppLocaleUtils.findDeviceLocale();
    return AppLocaleUtils.parse(tag);
  }

  List<AppLocale> get supportedLocales => AppLocale.values;
}
```

---

## Option B: Official gen-l10n (ARB)

Use when the team prefers the Flutter-standard toolchain with no extra packages.

### Setup

```yaml
# pubspec.yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.2

flutter:
  generate: true   # enables flutter gen-l10n
```

```yaml
# l10n.yaml (project root)
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
use-escaping: true
```

### app_en.arb — Template

```json
{
  "@@locale": "en",

  "authLoginTitle": "Sign In",
  "@authLoginTitle": { "description": "Login screen title" },

  "productDetailPrice": "Price: {price}",
  "@productDetailPrice": {
    "placeholders": { "price": { "type": "String" } }
  },

  "productListItemCount": "{count, plural, =0{No items} =1{1 item} other{{count} items}}",
  "@productListItemCount": {
    "placeholders": { "count": { "type": "int" } }
  },

  "greetingByGender": "{gender, select, male{Hello, Mr. {name}!} female{Hello, Ms. {name}!} other{Hello, {name}!}}",
  "@greetingByGender": {
    "placeholders": {
      "gender": { "type": "String" },
      "name": { "type": "String" }
    }
  }
}
```

### Usage

```dart
// Extension for shorter access
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

// In widgets:
Text(context.l10n.authLoginTitle)
Text(context.l10n.productDetailPrice(price: '\$9.99'))
Text(context.l10n.productListItemCount(count: products.length))
```

---

## CI — Missing Translation Check

```yaml
# .github/workflows/l10n_check.yml
name: L10n Check
on: [pull_request]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - name: Check missing translations (slang)
        run: dart run slang analyze --exit-code 1
      # OR for gen-l10n:
      # - name: Validate ARB files
      #   run: flutter gen-l10n && echo "✅ All translations valid"
```

---

## ARB Developer Workflow

This section explains how to create, maintain, and extend ARB files step by step.
Every developer working on a feature that adds user-visible text must follow this workflow.

---

### Step 1 — Project Setup (first time only)

```bash
# 1. Ensure flutter_localizations is in pubspec.yaml (see Setup above)

# 2. Create the l10n directory
mkdir -p lib/l10n

# 3. Create the base locale template file
touch lib/l10n/app_en.arb

# 4. Add the minimum valid content to app_en.arb
cat > lib/l10n/app_en.arb << 'EOF'
{
  "@@locale": "en"
}
EOF

# 5. Create l10n.yaml at the project root (see l10n.yaml Configuration above)

# 6. Run gen-l10n to verify the setup works
flutter gen-l10n
```

---

### Step 2 — Adding a New Translation Key

Every new user-visible string needs an entry in **all** ARB files.
Always start with the base locale (`app_en.arb`), then add to the others.

#### 2a. Add to the base locale (app_en.arb)

```json
{
  "@@locale": "en",

  "existingKey": "Existing value",

  "newFeatureTitle": "New Feature",
  "@newFeatureTitle": {
    "description": "Title of the new feature screen"
  },

  "newFeatureDescription": "This feature does {action} for {count} items.",
  "@newFeatureDescription": {
    "description": "Description with parameters",
    "placeholders": {
      "action": {
        "type": "String",
        "description": "The action being performed"
      },
      "count": {
        "type": "int",
        "description": "Number of items"
      }
    }
  },

  "newFeatureItemCount": "{count, plural, =0{No items} =1{One item} other{{count} items}}",
  "@newFeatureItemCount": {
    "description": "Plural form for item count",
    "placeholders": {
      "count": { "type": "int" }
    }
  }
}
```

#### 2b. Add the same key to every other locale file

```json
// app_es.arb
{
  "@@locale": "es",
  "newFeatureTitle": "Nueva función",
  "newFeatureDescription": "Esta función realiza {action} para {count} elementos.",
  "newFeatureItemCount": "{count, plural, =0{Sin elementos} =1{Un elemento} other{{count} elementos}}"
}
```

> **Rule:** A key added to `app_en.arb` MUST be added to all other locale files
> in the same PR. The CI check will fail if any locale is missing a key.

#### 2c. Regenerate the Dart code

```bash
flutter gen-l10n
```

#### 2d. Use the new key in your widget

```dart
Text(context.l10n.newFeatureTitle)
Text(context.l10n.newFeatureDescription(action: 'sync', count: 5))
Text(context.l10n.newFeatureItemCount(3))
```

---

### Step 3 — Adding a New Language

When the app needs to support a new locale (e.g., French `fr`):

#### 3a. Create the new ARB file

```bash
# Copy the base locale as a starting point
cp lib/l10n/app_en.arb lib/l10n/app_fr.arb
```

#### 3b. Update the locale metadata

```json
// lib/l10n/app_fr.arb
{
  "@@locale": "fr",

  "commonOk": "OK",
  "commonCancel": "Annuler",
  "commonLoading": "Chargement...",
  "authLoginTitle": "Se connecter",
  "authLoginSubmitButton": "Se connecter"
  // ... translate all keys
}
```

#### 3c. Add to l10n.yaml preferred locales

```yaml
# l10n.yaml
preferred-supported-locales:
  - en
  - es
  - ar
  - pt_BR
  - fr    # ← add here
```

#### 3d. Regenerate and verify

```bash
flutter gen-l10n

# Verify the new locale appears in supportedLocales
# AppLocalizations.supportedLocales should now include Locale('fr')
```

#### 3e. Add to the language selector UI

```dart
// lib/core/l10n/widgets/language_selector.dart
static const _languages = [
  (locale: Locale('en'), label: 'English',   flag: '🇺🇸'),
  (locale: Locale('es'), label: 'Español',   flag: '🇪🇸'),
  (locale: Locale('ar'), label: 'العربية',   flag: '🇸🇦'),
  (locale: Locale('fr'), label: 'Français',  flag: '🇫🇷'),  // ← add here
];
```

---

### Step 4 — Modifying an Existing Key

When a string changes (copy update, rebranding, UX improvement):

```bash
# 1. Update the value in app_en.arb (base locale)
# 2. Update the same key in ALL other locale files
# 3. Regenerate
flutter gen-l10n
# 4. Verify no compile errors — the key name didn't change, only the value
```

> **Never rename a key** without updating all call sites in the codebase.
> Renaming a key is a breaking change — treat it like a refactor.

---

### Step 5 — Removing a Key

```bash
# 1. Remove the key from app_en.arb
# 2. Remove the same key from ALL other locale files
# 3. Remove all usages in the codebase (context.l10n.keyName)
# 4. Regenerate — gen-l10n will fail if any usage still references the removed key
flutter gen-l10n
```

---

### ARB File Anatomy — Quick Reference

```json
{
  "@@locale": "en",                          // ← locale identifier (required)

  "simpleKey": "Simple string",              // ← key: value
  "@simpleKey": {                            // ← metadata (optional but recommended)
    "description": "Shown on the home screen"
  },

  "keyWithParam": "Hello, {name}!",          // ← string with parameter
  "@keyWithParam": {
    "placeholders": {
      "name": { "type": "String" }           // ← parameter type declaration
    }
  },

  "keyWithPlural": "{count, plural, =0{None} =1{One} other{{count} items}}",
  "@keyWithPlural": {
    "placeholders": {
      "count": { "type": "int" }
    }
  },

  "keyWithSelect": "{status, select, active{Active} inactive{Inactive} other{Unknown}}",
  "@keyWithSelect": {
    "placeholders": {
      "status": { "type": "String" }
    }
  },

  "keyWithDate": "Created on {date}",
  "@keyWithDate": {
    "placeholders": {
      "date": {
        "type": "DateTime",
        "format": "yMMMd",                   // ← intl DateFormat pattern
        "isCustomDateFormat": "false"
      }
    }
  }
}
```

---

### Common ARB Mistakes

```json
// ❌ Missing @metadata for keys with parameters — gen-l10n will fail
"greeting": "Hello, {name}!"

// ✅ Always declare placeholders
"greeting": "Hello, {name}!",
"@greeting": {
  "placeholders": { "name": { "type": "String" } }
}

// ❌ Inconsistent key across locales — CI will catch this
// app_en.arb: "authLoginTitle"
// app_es.arb: "auth_login_title"   ← different name

// ✅ Exact same key name in every locale file
// app_en.arb: "authLoginTitle": "Sign In"
// app_es.arb: "authLoginTitle": "Iniciar sesión"

// ❌ Hardcoded string in widget — not translatable
Text('Sign In')

// ✅ Always use the generated accessor
Text(context.l10n.authLoginTitle)

// ❌ Plural implemented in Dart — breaks for languages with complex plural rules
Text(count == 1 ? '1 item' : '$count items')

// ✅ Use ICU plural in ARB — handles all languages correctly
Text(context.l10n.productListItemCount(count))
```

---

### Developer Checklist — Per Feature

Before opening a PR that adds or changes user-visible text:

- [ ] New strings added to `app_en.arb` with `@metadata` and `description`
- [ ] Same keys added to **all** other locale files (`app_es.arb`, `app_ar.arb`, etc.)
- [ ] `flutter gen-l10n` runs without errors
- [ ] No hardcoded strings in widgets — all use `context.l10n.*`
- [ ] Plurals use ICU syntax in ARB — not Dart ternary
- [ ] Dates/numbers use `intl` formatters — not `toString()`
- [ ] Key names follow `featureSubjectAction` camelCase convention
