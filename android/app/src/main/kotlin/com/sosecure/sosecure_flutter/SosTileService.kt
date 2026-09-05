package com.sosecure.sosecure_flutter

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

// Botón de SOS en el panel de Ajustes Rápidos de Android (swipe desde arriba).
// Es otro "origen de gesto" externo a la app, igual que el botón de volumen
// con pantalla apagada (VolumeSosDetector.kt) — por eso reutiliza exactamente
// el mismo camino (VolumeSosDetector.fire): entrega el trigger directo al
// motor de Flutter si sigue vivo, o guarda un pending-trigger y levanta
// MainActivity si la app está cerrada. No requiere wiring nuevo del lado
// Dart, ya que consumePendingTrigger()/el EventChannel ya están conectados a
// sos_provider.dart vía volume_sos_provider.dart.
class SosTileService : TileService() {
    override fun onClick() {
        super.onClick()
        VolumeSosDetector.fire(applicationContext)
    }

    override fun onStartListening() {
        super.onStartListening()
        // Siempre disponible/activo — no representa un estado on/off como el
        // resto de los tiles del sistema, es un disparador de una sola acción.
        qsTile?.state = Tile.STATE_ACTIVE
        qsTile?.updateTile()
    }
}
