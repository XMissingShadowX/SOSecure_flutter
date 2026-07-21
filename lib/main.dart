import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/supabase_client.dart';

// Códigos de idioma no estándar (nah, myn, tze) igual que lib/i18n.ts del proyecto Next.js —
// easy_localization no los conoce nativamente, pero solo necesita que el nombre de archivo
// en assets/translations/ coincida con el languageCode del Locale.
const supportedLocales = [
  Locale('es'),
  Locale('en'),
  Locale('nah'),
  Locale('myn'),
  Locale('tze'),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await initSupabase();

  runApp(
    EasyLocalization(
      supportedLocales: supportedLocales,
      path: 'assets/translations',
      fallbackLocale: const Locale('es'),
      startLocale: const Locale('es'),
      child: const ProviderScope(child: SosecureApp()),
    ),
  );
}
