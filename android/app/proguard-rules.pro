# SOSecure - reglas R8/ProGuard
# La mayoría de los plugins (camera, geolocator, permission_handler,
# flutter_foreground_task, speech_to_text, record, flutter_map, video_player,
# connectivity_plus, gal, share_plus, url_launcher) traen su propio
# consumer-rules.pro dentro del AAR, que AGP fusiona automáticamente.
# supabase_flutter y sus dependencias son 100% Dart: no hay SDK nativo de
# Supabase en Android, por lo que R8 no las afecta (el código Dart se
# compila aparte con el AOT compiler de Dart, no con R8).

# Clases propias de la app: los handlers de MethodChannel/EventChannel
# (MainActivity, VolumeSosService, SosTileService, VolumeSosBootReceiver)
# se resuelven por nombre desde Dart.
-keep class com.sosecure.sosecure_flutter.** { *; }

# flutter_local_notifications (paquete legado com.dexterous) programa
# alarmas cuyo receiver lo resuelve el sistema fuera de cualquier llamada
# en vivo; conviene protegerlo para no perder alertas programadas.
-keep class com.dexterous.** { *; }

# Números de línea legibles en reportes de crash.
-keepattributes SourceFile,LineNumberTable

# Regla defensiva estándar de Flutter: evita un warning conocido de R8 por
# las clases de Play Core para "deferred components", aunque esta app no
# los use.
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn com.google.android.play.core.**
