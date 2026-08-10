package com.sosecure.sosecure_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import io.flutter.plugin.common.EventChannel

// Contador de pulsaciones del gesto de SOS por botón de volumen. Vive en un
// `object` (no en la Activity ni en el Service) porque las pulsaciones llegan
// desde tres orígenes distintos según dónde esté la app:
//
//   · Activity en primer plano   -> MainActivity.dispatchKeyEvent
//   · pantalla apagada/bloqueada -> VolumeSosService (MediaSession + observer)
//   · app cerrada                -> igual que el anterior, el servicio sobrevive
//
// Antes el conteo vivía en Dart (volume_sos_provider.dart) y solo se alimentaba
// del primer origen, así que el gesto simplemente no existía con la pantalla
// apagada — que es justo cuando hace falta. Ahora el conteo es nativo y único,
// y Dart solo configura los umbrales y reacciona al disparo.
object VolumeSosDetector {
    // Etiqueta única para seguir el gesto entero desde logcat:
    //   adb logcat -s SOSecureVolume:D
    const val TAG = "SOSecureVolume"

    const val PREFS = "sosecure_volume_sos"
    const val KEY_ENABLED = "background_enabled"
    const val KEY_PRESSES = "presses"
    const val KEY_WINDOW_MS = "window_ms"
    const val KEY_PENDING_TRIGGER = "pending_trigger_at"
    const val EXTRA_TRIGGER = "sosecure_volume_trigger"

    private const val DEFAULT_PRESSES = 5
    private const val DEFAULT_WINDOW_MS = 3000

    // Una misma pulsación física puede llegar por dos caminos a la vez (la
    // MediaSession la intercepta Y el ContentObserver ve el cambio de volumen
    // que provocamos al reenviarla al AudioManager). Dos avisos separados por
    // menos de esto son la misma tecla.
    private const val DEDUP_MS = 120L

    // Un disparo pendiente más viejo que esto ya no se consume al abrir la app:
    // sería activar un SOS por un gesto de hace horas.
    private const val PENDING_TTL_MS = 2 * 60 * 1000L

    private const val CHANNEL_TRIGGER = "sosecure_volume_sos_trigger"
    private const val NOTIFICATION_TRIGGER = 503

    private val pressTimes = ArrayDeque<Long>()
    private var lastPressAt = 0L

    @Volatile private var presses = DEFAULT_PRESSES
    @Volatile private var windowMs = DEFAULT_WINDOW_MS

    fun loadConfig(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        presses = prefs.getInt(KEY_PRESSES, DEFAULT_PRESSES)
        windowMs = prefs.getInt(KEY_WINDOW_MS, DEFAULT_WINDOW_MS)
    }

    fun configure(context: Context, presses: Int, windowMs: Int, backgroundEnabled: Boolean) {
        this.presses = presses
        this.windowMs = windowMs
        synchronized(pressTimes) { pressTimes.clear() }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putInt(KEY_PRESSES, presses)
            .putInt(KEY_WINDOW_MS, windowMs)
            .putBoolean(KEY_ENABLED, backgroundEnabled)
            .apply()
    }

    fun isBackgroundEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, true)

    /** Devuelve el instante del disparo pendiente (y lo borra), o null si no hay. */
    fun consumePendingTrigger(context: Context): Long? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val at = prefs.getLong(KEY_PENDING_TRIGGER, 0L)
        if (at == 0L) return null
        prefs.edit().remove(KEY_PENDING_TRIGGER).apply()
        return if (System.currentTimeMillis() - at <= PENDING_TTL_MS) at else null
    }

    fun registerPress(context: Context, source: String) {
        val now = System.currentTimeMillis()
        val reached: Boolean
        val count: Int
        synchronized(pressTimes) {
            if (now - lastPressAt < DEDUP_MS) {
                Log.d(TAG, "pulsación duplicada ignorada ($source)")
                return
            }
            lastPressAt = now
            while (pressTimes.isNotEmpty() && now - pressTimes.first() >= windowMs) {
                pressTimes.removeFirst()
            }
            pressTimes.addLast(now)
            count = pressTimes.size
            reached = count >= presses
            if (reached) pressTimes.clear()
        }
        Log.d(TAG, "pulsación $count/$presses ($source, ventana ${windowMs}ms)")
        VolumeSosBridge.emitPress(source, now)
        if (reached) fire(context)
    }

    private fun fire(context: Context) {
        val ctx = context.applicationContext
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(KEY_PENDING_TRIGGER, System.currentTimeMillis())
            .apply()

        // El proceso puede estar dormido con la pantalla apagada: sin esto,
        // arrancar la Activity o dejar que Dart hable con la red se queda a
        // medias. 20s alcanza para que la app tome el relevo.
        acquireBriefWakeLock(ctx)
        vibrate(ctx)

        // Si el motor de Flutter sigue vivo (app en segundo plano con la
        // pantalla apagada, el caso normal) el SOS se activa sin sacar la app
        // a primer plano, que además es lo discreto. Si no hay nadie
        // escuchando, la app está cerrada: hay que levantarla.
        if (VolumeSosBridge.emitTrigger()) {
            Log.d(TAG, "DISPARO — entregado al motor de Flutter (app viva)")
        } else {
            Log.d(TAG, "DISPARO — sin motor de Flutter, levantando la app")
            wakeUpApp(ctx)
        }
    }

    private fun wakeUpApp(ctx: Context) {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(EXTRA_TRIGGER, true)
        }
        val pending = PendingIntent.getActivity(
            ctx,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val manager = ctx.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_TRIGGER,
                    "SOS por botón de volumen",
                    NotificationManager.IMPORTANCE_HIGH,
                )
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, CHANNEL_TRIGGER)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        // fullScreenIntent: con el teléfono bloqueado, Android abre la app
        // directamente en vez de mostrar solo un aviso. Si el sistema no le
        // concede ese privilegio a la app, degrada a notificación flotante y
        // el startActivity() de abajo es el segundo intento.
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("SOSecure")
            .setContentText("Gesto de emergencia detectado — abriendo la app")
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setOngoing(false)
            .setFullScreenIntent(pending, true)
            .build()
        manager.notify(NOTIFICATION_TRIGGER, notification)

        try {
            ctx.startActivity(intent)
        } catch (_: Exception) {
            // Android 10+ puede bloquear el arranque de actividades desde
            // segundo plano; la notificación de pantalla completa ya quedó
            // publicada como camino alterno.
        }
    }

    private fun acquireBriefWakeLock(ctx: Context) {
        try {
            val power = ctx.getSystemService(PowerManager::class.java)
            val lock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sosecure:volume-sos")
            lock.setReferenceCounted(false)
            lock.acquire(20_000L)
            Handler(Looper.getMainLooper()).postDelayed({
                if (lock.isHeld) lock.release()
            }, 20_000L)
        } catch (_: Exception) {
        }
    }

    private fun vibrate(ctx: Context) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                ctx.getSystemService(VibratorManager::class.java).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                ctx.getSystemService(Vibrator::class.java)
            }
            val pattern = longArrayOf(0, 400, 100, 400)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, -1)
            }
        } catch (_: Exception) {
        }
    }
}

// Puente hacia el EventChannel del motor de Flutter. El sink lo pone y lo
// quita MainActivity: existe mientras haya un motor vivo, y desaparece cuando
// la app se cierra del todo — que es exactamente la señal que usa
// VolumeSosDetector.fire() para decidir si basta con avisar a Dart o hay que
// levantar la app entera.
object VolumeSosBridge {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    var eventSink: EventChannel.EventSink? = null

    fun emitPress(source: String, timestamp: Long) {
        val sink = eventSink ?: return
        main.post { sink.success(mapOf("type" to "press", "source" to source, "timestamp" to timestamp)) }
    }

    /** @return true si había un motor de Flutter escuchando. */
    fun emitTrigger(): Boolean {
        val sink = eventSink ?: return false
        main.post {
            sink.success(mapOf("type" to "trigger", "timestamp" to System.currentTimeMillis()))
        }
        return true
    }
}
