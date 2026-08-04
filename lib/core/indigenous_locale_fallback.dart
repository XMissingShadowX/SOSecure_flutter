import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Flutter's built-in localization delegates (Material/Cupertino/Widgets) solo
// reconocen códigos ISO estándar — 'nah' (náhuatl), 'myn' (maya yucateco) y
// 'tze' (tseltal) no están en su lista, así que `isSupported()` devuelve
// false para ellos. Como app.dart pasa `locale: context.locale` de forma
// explícita (no null), MaterialApp nunca llega a intentar un
// localeResolutionCallback — sencillamente no encuentra ningún delegado que
// sirva MaterialLocalizations/CupertinoLocalizations/WidgetsLocalizations
// para esos tres códigos, y cualquier widget que los necesite (casi
// cualquier widget de Material) lanza "No MaterialLocalizations found" en
// cuanto se monta.
//
// Estos delegados de fallback interceptan esos tres códigos y sirven el
// contenido en español para las localizaciones NATIVAS de Flutter (textos
// como "OK", "Cancelar" de diálogos, formato de fecha del selector, etc.).
// Esto es independiente de las traducciones propias de la app (easy_localization
// / los .tr()), que si soportan estos códigos porque no dependen de la lista
// de locales de Flutter, solo de los archivos en assets/translations/.
const _indigenousCodes = {'nah', 'myn', 'tze'};

class IndigenousMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const IndigenousMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _indigenousCodes.contains(locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('es'));

  @override
  bool shouldReload(IndigenousMaterialLocalizationsDelegate old) => false;
}

class IndigenousCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const IndigenousCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _indigenousCodes.contains(locale.languageCode);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('es'));

  @override
  bool shouldReload(IndigenousCupertinoLocalizationsDelegate old) => false;
}

class IndigenousWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const IndigenousWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _indigenousCodes.contains(locale.languageCode);

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(const Locale('es'));

  @override
  bool shouldReload(IndigenousWidgetsLocalizationsDelegate old) => false;
}

const List<LocalizationsDelegate> indigenousLocaleFallbackDelegates = [
  IndigenousMaterialLocalizationsDelegate(),
  IndigenousCupertinoLocalizationsDelegate(),
  IndigenousWidgetsLocalizationsDelegate(),
];
