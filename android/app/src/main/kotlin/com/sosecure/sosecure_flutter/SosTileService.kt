package com.sosecure.sosecure_flutter

import android.graphics.drawable.Icon
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
        // El manifest ya declara android:icon en el <service>, pero no todos
        // los fabricantes lo usan como ícono por defecto del Tile en tiempo de
        // ejecución (mismo tipo de inconsistencia que ya se vio en este
        // dispositivo con el nombre del permiso) — se fija explícito para no
        // depender de ese comportamiento.
        //
        // drawable/ic_tile_sos_logo — copia aplanada (fondo+logo) de
        // mipmap-xxxhdpi/ic_launcher.png bajo un nombre de recurso propio.
        // Dos intentos previos fallaron: mipmap/ic_launcher resuelve al ícono
        // ADAPTATIVO (mipmap-anydpi-v26/ic_launcher.xml) y renderizaba un
        // cuadro negro sólido; ic_launcher_foreground es solo la capa de
        // primer plano del adaptativo, diseñada para verse recién DESPUÉS de
        // que el launcher la recorta/escala a su "safe zone" — usada cruda se
        // ve diminuta dentro de un lienzo mucho más grande. Esta copia es un
        // PNG plano normal, del mismo tamaño de lienzo completo que cualquier
        // ícono de status bar, así que no tiene ese problema de escala.
        qsTile?.icon = Icon.createWithResource(this, R.drawable.ic_tile_sos_logo)
        qsTile?.updateTile()
    }
}
