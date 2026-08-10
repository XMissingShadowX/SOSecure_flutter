package com.sosecure.sosecure_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// Tras reiniciar el teléfono nadie abre la app por su cuenta, así que sin esto
// el gesto de emergencia quedaría muerto hasta la próxima vez que el usuario
// entrara a SOSecure — justo el escenario que hace inútil una función de
// seguridad. BOOT_COMPLETED está exento de las restricciones de arranque de
// servicios en primer plano, así que se puede levantar el servicio desde aquí.
class VolumeSosBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }
        if (!VolumeSosDetector.isBackgroundEnabled(context)) return
        VolumeSosDetector.loadConfig(context)
        VolumeSosService.start(context)
    }
}
