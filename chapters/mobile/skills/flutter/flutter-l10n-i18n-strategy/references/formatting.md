# Locale-Aware Formatting — intl Package

The `intl` package handles all locale-sensitive formatting: dates, times,
numbers, and currencies. Always use it — never `DateTime.toString()`
or manual string concatenation for user-facing values.

```yaml
dependencies:
  intl: ^0.20.2
```

---

## Initialization

```dart
// main.dart — initialize date formatting for all locales
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting(); // loads all locale data
  runApp(const App());
}
```

---

## Date Formatting

```dart
import 'package:intl/intl.dart';

final date = DateTime(2026, 4, 29);

// ✅ Named constructors — locale-aware
DateFormat.yMMMd('en_US').format(date)   // Apr 29, 2026
DateFormat.yMMMd('es').format(date)      // 29 abr 2026
DateFormat.yMMMd('pt_BR').format(date)   // 29 de abr. de 2026

// ✅ Full date
DateFormat.yMMMMEEEEd('en_US').format(date)  // Wednesday, April 29, 2026
DateFormat.yMMMMEEEEd('es').format(date)     // miércoles, 29 de abril de 2026
DateFormat.yMMMMEEEEd('pt_BR').format(date)  // quarta-feira, 29 de abril de 2026

// ✅ Short date
DateFormat.yMd('en_US').format(date)   // 4/29/2026
DateFormat.yMd('es').format(date)      // 29/4/2026
DateFormat.yMd('pt_BR').format(date)   // 29/04/2026

// ✅ Time (12h)
DateFormat.jm('en_US').format(date)    // 12:00 PM
DateFormat.jm('es').format(date)       // 12:00
DateFormat.jm('pt_BR').format(date)    // 12:00

// ✅ Time (24h)
DateFormat.Hm('en_US').format(date)    // 12:00
DateFormat.Hm('es').format(date)       // 12:00
DateFormat.Hm('pt_BR').format(date)    // 12:00

// ✅ Date + time
DateFormat.yMMMd('en_US').add_jm().format(date)   // Apr 29, 2026 12:00 PM
DateFormat.yMMMd('es').add_jm().format(date)      // 29 abr 2026 12:00
DateFormat.yMMMd('pt_BR').add_jm().format(date)   // 29 de abr. de 2026 12:00

// ✅ Custom pattern (use sparingly — prefer named constructors)
DateFormat('dd/MM/yyyy', 'en_US').format(date)   // 29/04/2026
DateFormat('dd/MM/yyyy', 'es').format(date)      // 29/04/2026
DateFormat('dd/MM/yyyy', 'pt_BR').format(date)   // 29/04/2026
```

### Date Formatting Service

```dart
// lib/core/l10n/date_formatter.dart
import 'package:intl/intl.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class DateFormatter {
  String formatDate(DateTime date, String locale) =>
      DateFormat.yMMMd(locale).format(date);

  String formatDateFull(DateTime date, String locale) =>
      DateFormat.yMMMMEEEEd(locale).format(date);

  String formatDateShort(DateTime date, String locale) =>
      DateFormat.yMd(locale).format(date);

  String formatDateTime(DateTime date, String locale) =>
      DateFormat.yMMMd(locale).add_jm().format(date);

  String formatTime(DateTime date, String locale) =>
      DateFormat.jm(locale).format(date);
}
```

---

## Number Formatting

```dart
import 'package:intl/intl.dart';

final number = 1234567.89;

// ✅ Decimal — separator differs per locale
NumberFormat.decimalPattern('en_US').format(number)  // 1,234,567.89
NumberFormat.decimalPattern('es').format(number)     // 1.234.567,89
NumberFormat.decimalPattern('pt_BR').format(number)  // 1.234.567,89

// ✅ Percentage
NumberFormat.percentPattern('en_US').format(0.856)   // 86%
NumberFormat.percentPattern('es').format(0.856)      // 86%
NumberFormat.percentPattern('pt_BR').format(0.856)   // 86%

// ✅ Compact
NumberFormat.compact('en_US').format(1234567)        // 1.2M
NumberFormat.compact('es').format(1234567)           // 1.2 M
NumberFormat.compact('pt_BR').format(1234567)        // 1,2 mi

// ✅ Compact long
NumberFormat.compactLong('en_US').format(1234567)    // 1.2 million
NumberFormat.compactLong('es').format(1234567)       // 1.2 millones
NumberFormat.compactLong('pt_BR').format(1234567)    // 1,2 milhão
```

---

## Currency Formatting

```dart
import 'package:intl/intl.dart';

final amount = 1234.56;

// ✅ With explicit currency symbol
NumberFormat.currency(locale: 'en_US', symbol: r'$').format(amount)    // $1,234.56
NumberFormat.currency(locale: 'es_MX', symbol: r'$').format(amount)    // $1,234.56
NumberFormat.currency(locale: 'es_CO', symbol: r'$').format(amount)    // $1.234,56
NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(amount)   // R$1.234,56

// ✅ With ISO 4217 currency code (no symbol)
NumberFormat.currency(locale: 'en_US', name: 'USD').format(amount)     // USD1,234.56
NumberFormat.currency(locale: 'es_MX', name: 'MXN').format(amount)     // MXN1,234.56
NumberFormat.currency(locale: 'es_CO', name: 'COP').format(amount)     // COP1.234,56
NumberFormat.currency(locale: 'pt_BR', name: 'BRL').format(amount)     // BRL1.234,56

// ✅ Simple currency — uses locale default symbol
NumberFormat.simpleCurrency(locale: 'en_US').format(amount)    // $1,234.56
NumberFormat.simpleCurrency(locale: 'es_MX').format(amount)    // MX$1,234.56
NumberFormat.simpleCurrency(locale: 'es_CO').format(amount)    // $1.234,56
NumberFormat.simpleCurrency(locale: 'pt_BR').format(amount)    // R$1.234,56

// ✅ Compact currency
NumberFormat.compactCurrency(locale: 'en_US', symbol: r'$').format(1234567)    // $1.2M
NumberFormat.compactCurrency(locale: 'es_MX', symbol: r'$').format(1234567)   // $1.2M
NumberFormat.compactCurrency(locale: 'es_CO', symbol: r'$').format(1234567)   // $1,2 M
NumberFormat.compactCurrency(locale: 'pt_BR', symbol: 'R\$').format(1234567)  // R$1,2 mi
```

### Currency Formatter Service

```dart
// lib/core/l10n/currency_formatter.dart
import 'package:intl/intl.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class CurrencyFormatter {
  /// Format an amount stored in cents (e.g., 123456 → $1,234.56).
  /// [currencyCode] is ISO 4217: 'USD', 'MXN', 'COP', 'BRL'.
  String formatFromCents({
    required int amountInCents,
    required String currencyCode,
    required String locale,
  }) {
    final amount = amountInCents / 100.0;
    return NumberFormat.currency(
      locale: locale,
      name: currencyCode,
    ).format(amount);
  }

  // Usage examples:
  // formatFromCents(amountInCents: 123456, currencyCode: 'USD', locale: 'en_US') → USD1,234.56
  // formatFromCents(amountInCents: 123456, currencyCode: 'MXN', locale: 'es_MX') → MXN1,234.56
  // formatFromCents(amountInCents: 123456, currencyCode: 'COP', locale: 'es_CO') → COP1.234,56
  // formatFromCents(amountInCents: 123456, currencyCode: 'BRL', locale: 'pt_BR') → BRL1.234,56

  /// Format with explicit symbol.
  String formatWithSymbol({
    required double amount,
    required String symbol,
    required String locale,
  }) =>
      NumberFormat.currency(locale: locale, symbol: symbol).format(amount);

  /// Format compact (e.g., $1.2M).
  String formatCompact({
    required double amount,
    required String symbol,
    required String locale,
  }) =>
      NumberFormat.compactCurrency(locale: locale, symbol: symbol).format(amount);
}
```

---

## Relative Time

```dart
// lib/core/l10n/relative_time_formatter.dart
// intl does not have a built-in relative time formatter.
// Use ARB plurals for the strings + intl for number formatting.

// app_en.arb:
// "relativeTimeJustNow": "Just now"
// "relativeTimeMinutesAgo": "{count, plural, =1{1 minute ago} other{{count} minutes ago}}"
// "relativeTimeHoursAgo": "{count, plural, =1{1 hour ago} other{{count} hours ago}}"
// "relativeTimeDaysAgo": "{count, plural, =1{1 day ago} other{{count} days ago}}"

// app_es.arb:
// "relativeTimeJustNow": "Justo ahora"
// "relativeTimeMinutesAgo": "{count, plural, =1{Hace 1 minuto} other{Hace {count} minutos}}"
// "relativeTimeHoursAgo": "{count, plural, =1{Hace 1 hora} other{Hace {count} horas}}"
// "relativeTimeDaysAgo": "{count, plural, =1{Hace 1 día} other{Hace {count} días}}"

// app_pt_BR.arb:
// "relativeTimeJustNow": "Agora mesmo"
// "relativeTimeMinutesAgo": "{count, plural, =1{Há 1 minuto} other{Há {count} minutos}}"
// "relativeTimeHoursAgo": "{count, plural, =1{Há 1 hora} other{Há {count} horas}}"
// "relativeTimeDaysAgo": "{count, plural, =1{Há 1 dia} other{Há {count} dias}}"

class RelativeTimeFormatter {
  static String format(DateTime date, AppLocalizations l10n, String locale) {
    final diff = DateTime.now().difference(date).abs();

    if (diff.inSeconds < 60) return l10n.relativeTimeJustNow;
    if (diff.inMinutes < 60) return l10n.relativeTimeMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24)   return l10n.relativeTimeHoursAgo(diff.inHours);
    if (diff.inDays < 7)     return l10n.relativeTimeDaysAgo(diff.inDays);
    return DateFormat.yMMMd(locale).format(date);
  }
}
```

---

## Common Mistakes

```dart
// ❌ Never use DateTime.toString() for display
Text(product.createdAt.toString())  // "2026-04-29 12:00:00.000"

// ✅ Always use DateFormat
Text(DateFormat.yMMMd(locale).format(product.createdAt))
// en_US → "Apr 29, 2026"
// es    → "29 abr 2026"
// pt_BR → "29 de abr. de 2026"

// ❌ Never concatenate currency manually
Text('\$${price.toStringAsFixed(2)}')  // always "$9.99" — wrong for pt_BR

// ✅ Always use NumberFormat.currency
Text(NumberFormat.currency(locale: locale, name: currencyCode).format(price))
// en_US + USD → "USD9.99"
// es_MX + MXN → "MXN9.99"
// es_CO + COP → "COP9,99"
// pt_BR + BRL → "BRL9,99"

// ❌ Never hardcode decimal/thousands separator
Text('${(price * 1.1).toStringAsFixed(2)}')  // "10.89" — wrong for es/pt_BR

// ✅ Use NumberFormat.decimalPattern
Text(NumberFormat.decimalPattern(locale).format(price * 1.1))
// en_US → "10.89"
// es    → "10,89"
// pt_BR → "10,89"
```
