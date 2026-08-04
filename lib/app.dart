import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/indigenous_locale_fallback.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'state/settings_provider.dart';

class SosecureApp extends ConsumerWidget {
  const SosecureApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appThemeModeProvider);
    return MaterialApp.router(
      title: 'SOSecure',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      // Los delegados de fallback van ANTES que context.localizationDelegates:
      // Localizations elige el primer delegado de la lista cuyo isSupported()
      // sea true para cada tipo (MaterialLocalizations, etc). 'nah'/'myn'/'tze'
      // no son códigos ISO que GlobalMaterialLocalizations reconozca, así que
      // sin este fallback la app crashea con "No MaterialLocalizations found"
      // en cuanto el locale activo es uno de esos tres (ver
      // core/indigenous_locale_fallback.dart para el detalle).
      localizationsDelegates: [
        ...indigenousLocaleFallbackDelegates,
        ...context.localizationDelegates,
      ],
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      routerConfig: appRouter,
    );
  }
}
