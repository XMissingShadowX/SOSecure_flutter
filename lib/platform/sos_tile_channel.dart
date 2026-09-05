import 'dart:io';

import 'package:flutter/services.dart';

// Puente hacia TileService.requestAddTile() (Android 13+) — pide al sistema
// mostrar el diálogo nativo de "agregar este tile a Ajustes Rápidos"
// directamente, en vez de depender del picker manual de "Editar Ajustes
// Rápidos" (que en algunos fabricantes con System UI muy personalizada,
// como este Cubot KingKong 9 con MediaTek, no llega a listar tiles de
// terceros pese a que el manifest está correctamente declarado).
class SosTileChannel {
  static const _channel = MethodChannel(
    'com.sosecure.sosecure_flutter/sos_tile',
  );

  // Códigos de TileService.requestAddTile() (android.service.quicksettings):
  // 0 = TILE_ALREADY_ADDED, 1 = TILE_ADDED, 2 = TILE_NOT_ADDED (el usuario
  // rechazó el diálogo). -1 (nuestro propio código) = API no disponible
  // (Android < 13) o no es Android.
  static Future<int> requestAddTile() async {
    if (!Platform.isAndroid) return -1;
    final result = await _channel.invokeMethod<int>('requestAddTile');
    return result ?? -1;
  }
}
