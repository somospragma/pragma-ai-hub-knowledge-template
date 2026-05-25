# RTL, Advanced Patterns, and Platform Configuration

## RTL Layout Support

RTL (Right-to-Left) languages: Arabic (`ar`), Hebrew (`he`), Persian (`fa`), Urdu (`ur`).

Flutter handles RTL automatically when the locale is set — but only if you use
directional-aware widgets and properties.

### Directional-Aware Properties

```dart
// ✅ Use EdgeInsetsDirectional — adapts to text direction
Padding(
  padding: const EdgeInsetsDirectional.only(
    start: 16,   // left in LTR, right in RTL
    end: 8,      // right in LTR, left in RTL
    top: 12,
    bottom: 12,
  ),
)

// ❌ Avoid EdgeInsets.only(left:) — always left regardless of direction
Padding(padding: const EdgeInsets.only(left: 16))

// ✅ AlignmentDirectional
Align(alignment: AlignmentDirectional.centerStart)  // left in LTR, right in RTL
Align(alignment: AlignmentDirectional.centerEnd)

// ❌ Alignment.centerLeft — always left
Align(alignment: Alignment.centerLeft)
```

### Directional-Aware Widgets

```dart
// ✅ Row — automatically reverses children in RTL
Row(
  children: [
    const Icon(Icons.arrow_back),  // ← in LTR, → in RTL
    const SizedBox(width: 8),
    Text(context.t.common.back),
  ],
)

// ✅ ListTile — leading/trailing swap in RTL automatically
ListTile(
  leading: const Icon(Icons.person),
  title: Text(user.name),
  trailing: const Icon(Icons.chevron_right),
)

// ✅ TextDirection.rtl for explicit override (rare)
Directionality(
  textDirection: TextDirection.rtl,
  child: Text('مرحبا'),
)
```

### Icons That Should Mirror in RTL

```dart
// Some icons have directional meaning and should mirror in RTL
// Use Transform.flip or Icon with textDirection
Icon(
  Icons.arrow_forward,
  textDirection: Directionality.of(context), // mirrors in RTL
)

// Or use the semantic icons that auto-mirror:
// Icons.arrow_back_ios → mirrors to arrow_forward_ios in RTL
// Icons.chevron_right → mirrors to chevron_left in RTL
```

### Detecting Current Text Direction

```dart
final isRtl = Directionality.of(context) == TextDirection.rtl;

// Use for conditional logic (rare — prefer directional widgets)
if (isRtl) {
  // RTL-specific behavior
}
```

---

## Locale-Specific Assets

Different locales may need different images (e.g., screenshots with localized text,
culturally appropriate illustrations).

```
assets/
├── images/
│   ├── hero_banner.png          ← default (en)
│   └── ar/
│       └── hero_banner.png      ← Arabic variant
```

```dart
// lib/core/l10n/locale_asset_resolver.dart
class LocaleAssetResolver {
  static String resolveImage(String assetName, String locale) {
    final localizedPath = 'assets/images/$locale/$assetName';
    // Check if locale-specific asset exists, fall back to default
    // In practice, use a try/catch with rootBundle.load
    return localizedPath;
  }
}

// Usage:
Image.asset(
  LocaleAssetResolver.resolveImage('hero_banner.png', locale),
  errorBuilder: (_, __, ___) => Image.asset('assets/images/hero_banner.png'),
)
```

---

## Platform App Name Localization

### Android

```xml
<!-- android/app/src/main/res/values/strings.xml (default) -->
<resources>
    <string name="app_name">MyApp</string>
</resources>

<!-- android/app/src/main/res/values-es/strings.xml -->
<resources>
    <string name="app_name">MiApp</string>
</resources>

<!-- android/app/src/main/res/values-ar/strings.xml -->
<resources>
    <string name="app_name">تطبيقي</string>
</resources>
```

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application
    android:label="@string/app_name"
    ...>
```

### iOS

```
ios/Runner/
├── InfoPlist.strings (Base)
├── en.lproj/
│   └── InfoPlist.strings
├── es.lproj/
│   └── InfoPlist.strings
└── ar.lproj/
    └── InfoPlist.strings
```

```
// ios/Runner/en.lproj/InfoPlist.strings
"CFBundleDisplayName" = "MyApp";
"CFBundleName" = "MyApp";

// ios/Runner/es.lproj/InfoPlist.strings
"CFBundleDisplayName" = "MiApp";
"CFBundleName" = "MiApp";
```

```xml
<!-- ios/Runner/Info.plist — add supported localizations -->
<key>CFBundleLocalizations</key>
<array>
    <string>en</string>
    <string>es</string>
    <string>ar</string>
    <string>pt-BR</string>
</array>
```

---

## Locale Persistence with BLoC

```dart
// lib/core/l10n/locale_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'locale_bloc.freezed.dart';
part 'locale_event.dart';
part 'locale_state.dart';

@singleton
class LocaleBloc extends Bloc<LocaleEvent, LocaleState> {
  static const _key = 'app_locale';

  LocaleBloc() : super(const LocaleState(locale: Locale('en'))) {
    on<LoadLocaleEvent>(_onLoad);
    on<ChangeLocaleEvent>(_onChange);
  }

  Future<void> _onLoad(
    LoadLocaleEvent event,
    Emitter<LocaleState> emit,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final tag = prefs.getString(_key);
    if (tag != null) {
      emit(LocaleState(locale: Locale(tag)));
    }
  }

  Future<void> _onChange(
    ChangeLocaleEvent event,
    Emitter<LocaleState> emit,
  ) async {
    emit(LocaleState(locale: event.locale));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, event.locale.languageCode);

    // Update slang locale
    LocaleSettings.setLocaleRaw(event.locale.toLanguageTag());
  }
}

// locale_event.dart
part of 'locale_bloc.dart';

@freezed
class LocaleEvent with _$LocaleEvent {
  const factory LocaleEvent.load() = LoadLocaleEvent;
  const factory LocaleEvent.change(Locale locale) = ChangeLocaleEvent;
}

// locale_state.dart
part of 'locale_bloc.dart';

@freezed
class LocaleState with _$LocaleState {
  const factory LocaleState({required Locale locale}) = _LocaleState;
}
```

```dart
// In MaterialApp — react to locale changes
BlocBuilder<LocaleBloc, LocaleState>(
  builder: (context, state) => MaterialApp.router(
    locale: state.locale,
    supportedLocales: AppLocaleUtils.supportedLocales,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routerConfig: GetIt.instance<AppRouter>().router,
  ),
)
```

---

## Language Selector Widget

```dart
// lib/core/l10n/widgets/language_selector.dart
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  static const _languages = [
    (locale: Locale('en'), label: 'English', flag: '🇺🇸'),
    (locale: Locale('es'), label: 'Español', flag: '🇪🇸'),
    (locale: Locale('ar'), label: 'العربية', flag: '🇸🇦'),
    (locale: Locale('pt', 'BR'), label: 'Português', flag: '🇧🇷'),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LocaleBloc, LocaleState>(
      builder: (context, state) => Column(
        children: _languages.map((lang) => RadioListTile<Locale>(
          value: lang.locale,
          groupValue: state.locale,
          title: Text('${lang.flag}  ${lang.label}'),
          onChanged: (locale) {
            if (locale != null) {
              context.read<LocaleBloc>().add(LocaleEvent.change(locale));
            }
          },
        )).toList(),
      ),
    );
  }
}
```

---

## Pseudo-Localization for Testing

Pseudo-localization replaces characters with accented equivalents to test
that the UI handles non-ASCII characters and longer strings correctly.

```dart
// lib/core/l10n/pseudo_locale.dart
// Use during development to catch layout issues before real translations arrive

// In slang.yaml, add a pseudo locale:
// pseudo_locale: pseudo

// This generates a pseudo translation that looks like:
// "Sign In" → "[Šïgñ Ïñ]"
// Helps detect:
// - Text overflow (pseudo strings are ~30% longer)
// - Missing font support for accented characters
// - Hardcoded strings that weren't extracted
```

---

## Translation Workflow at Scale

```
1. Developer adds new key to base locale (en.i18n.json)
2. CI runs `dart run slang analyze` → detects missing keys in other locales
3. CI fails → developer or translator is notified
4. Translator updates non-base locale files
5. CI passes → PR can be merged

Tools for translator collaboration:
- Localizely (supports ARB, JSON, YAML)
- Phrase (supports ARB, JSON)
- Crowdin (supports ARB, JSON, YAML)
- POEditor (supports JSON)
- Manual: export JSON → translate → import back
```

### Namespace Strategy for Large Apps

```yaml
# slang.yaml — enable namespaces for large apps
namespaces: true
input_directory: lib/l10n
```

```
lib/l10n/
├── en/
│   ├── common.i18n.json
│   ├── auth.i18n.json
│   ├── product.i18n.json
│   └── cart.i18n.json
└── es/
    ├── common.i18n.json
    ├── auth.i18n.json
    ├── product.i18n.json
    └── cart.i18n.json
```

```dart
// Access by namespace — same type-safe API
context.t.auth.login.title
context.t.product.detail.addToCart
context.t.common.error.network
```
