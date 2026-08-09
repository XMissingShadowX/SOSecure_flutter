import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/supabase_client.dart';
import 'platform/sos_foreground_service.dart';

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
  // No se hace `await` de nada relacionado al foreground service aquí: si esa llamada
  // nativa se cuelga o tarda, bloquearía runApp() indefinidamente y la app se quedaría
  // en el splash nativo sin avanzar (fue exactamente el bug de pantalla en blanco
  // detectado en el primer intento de esta fase). init() es sincrónico/rápido; el
  // permiso de notificación se pide más tarde, justo antes de iniciar el servicio.
  SosForegroundService.init();

  runApp(
    EasyLocalization(
      supportedLocales: supportedLocales,
      path: 'assets/translations',
      // Sin startLocale, easy_localization usa el idioma del teléfono cuando
      // está entre los soportados y cae a español cuando no. Antes se forzaba
      // español siempre, así que alguien con el celular en inglés recibía la
      // app en español hasta cambiarla a mano. La elección explícita del
      // usuario se sigue guardando y tiene prioridad sobre ambos.
      fallbackLocale: const Locale('es'),
      child: const ProviderScope(child: SosecureApp()),
    ),
  );
}
