package com.sosecure.sosecure_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.media.AudioManager
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log

// Servicio en primer plano que mantiene vivo el gesto de SOS por botón de
// volumen con la pantalla apagada, el teléfono bloqueado o la app cerrada.
//
// Android no entrega eventos de tecla a una Activity que no está en primer
// plano — por eso el `dispatchKeyEvent` de MainActivity (lo único que había)
// dejaba de funcionar en cuanto se apagaba la pantalla. Los dos caminos que sí
// funcionan con la pantalla apagada son:
//
//  1. MediaSession con volumen "remoto". El sistema enruta las teclas de
//     volumen a la sesión de medios activa en vez de al stream de audio, así
//     que llegan a VolumeProvider.onAdjustVolume incluso con la pantalla
//     apagada. Reenviamos el ajuste al AudioManager para que el volumen siga
//     cambiando de verdad: el gesto no debe secuestrar los botones.
//     Limitación conocida: si otra app está reproduciendo audio, su sesión
//     tiene prioridad y las teclas se van con ella. De ahí el segundo camino.
//
//  2. ContentObserver sobre Settings.System. Ve el cambio de volumen que
//     provoca cualquier pulsación que no hayamos interceptado. No detecta
//     pulsaciones con el volumen ya al máximo o al mínimo, por eso es respaldo
//     y no reemplazo. El contador deduplica lo que llega por ambos caminos.
class VolumeSosService : Service() {

    companion object {
        private const val CHANNEL_ID = "sosecure_volume_sos"
        private const val NOTIFICATION_ID = 502

        @Volatile
        var running = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, VolumeSosService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, VolumeSosService::class.java))
        }
    }

    private var mediaSession: MediaSession? = null
    private var volumeObserver: ContentObserver? = null

    // Con la pantalla apagada y sin nada reproduciéndose, las teclas de volumen
    // no tocan el stream de música sino el de timbre/notificaciones: vigilar
    // solo STREAM_MUSIC dejaría ciego al respaldo justo en el escenario que
    // esta clase existe para cubrir.
    private val watchedStreams = intArrayOf(
        AudioManager.STREAM_MUSIC,
        AudioManager.STREAM_RING,
        AudioManager.STREAM_NOTIFICATION,
        AudioManager.STREAM_ALARM,
    )
    private val lastStreamVolumes = HashMap<Int, Int>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        VolumeSosDetector.loadConfig(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        startMediaSession()
        startVolumeObserver()
        running = true
        Log.d(VolumeSosDetector.TAG, "servicio en primer plano activo (MediaSession + observer)")
        // START_STICKY: si Android mata el proceso por memoria, vuelve a
        // levantar el servicio — el gesto de emergencia no debería morirse
        // en silencio.
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        Log.d(VolumeSosDetector.TAG, "servicio detenido")
        volumeObserver?.let { contentResolver.unregisterContentObserver(it) }
        volumeObserver = null
        mediaSession?.let {
            it.isActive = false
            it.release()
        }
        mediaSession = null
        super.onDestroy()
    }

    private fun startInForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Gesto de emergencia",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description =
                    "Notificación permanente que mantiene activa la detección del botón de volumen con la pantalla apagada."
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        val open = PendingIntent.getActivity(
            this,
            1,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("SOSecure activo")
            .setContentText("Gesto del botón de volumen listo")
            .setContentIntent(open)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startMediaSession() {
        if (mediaSession != null) return
        val audio = getSystemService(AudioManager::class.java)
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)

        val provider = object : VolumeProvider(
            VOLUME_CONTROL_ABSOLUTE,
            max,
            audio.getStreamVolume(AudioManager.STREAM_MUSIC),
        ) {
            override fun onAdjustVolume(direction: Int) {
                if (direction != 0) {
                    VolumeSosDetector.registerPress(
                        this@VolumeSosService,
                        if (direction > 0) "up" else "down",
                    )
                    // El gesto NO se queda con los botones: el volumen cambia
                    // igual que siempre (con su panel en pantalla), o el
                    // usuario no podría subirle a la música con la app abierta.
                    audio.adjustStreamVolume(
                        AudioManager.STREAM_MUSIC,
                        if (direction > 0) AudioManager.ADJUST_RAISE else AudioManager.ADJUST_LOWER,
                        AudioManager.FLAG_SHOW_UI,
                    )
                }
                currentVolume = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
            }

            override fun onSetVolumeTo(volume: Int) {
                audio.setStreamVolume(AudioManager.STREAM_MUSIC, volume, AudioManager.FLAG_SHOW_UI)
                currentVolume = volume
            }
        }

        mediaSession = MediaSession(this, "SOSecureVolumeSos").apply {
            setPlaybackState(
                PlaybackState.Builder()
                    // Solo una sesión "reproduciendo" recibe las teclas de
                    // volumen del sistema. No se reproduce nada: es el estado
                    // mínimo para que el enrutado exista.
                    .setState(PlaybackState.STATE_PLAYING, 0L, 1f)
                    .setActions(PlaybackState.ACTION_PLAY_PAUSE)
                    .build()
            )
            setPlaybackToRemote(provider)
            isActive = true
        }
    }

    private fun startVolumeObserver() {
        if (volumeObserver != null) return
        val audio = getSystemService(AudioManager::class.java)
        for (stream in watchedStreams) {
            lastStreamVolumes[stream] = audio.getStreamVolume(stream)
        }

        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            // Settings.System notifica cualquier cambio de ajustes del sistema,
            // no solo de volumen: la pulsación se deduce de que el volumen de
            // alguno de los streams vigilados haya cambiado de verdad.
            override fun onChange(selfChange: Boolean) {
                var direction: String? = null
                for (stream in watchedStreams) {
                    val current = audio.getStreamVolume(stream)
                    val previous = lastStreamVolumes[stream] ?: current
                    if (current != previous && direction == null) {
                        direction = if (current > previous) "up" else "down"
                    }
                    lastStreamVolumes[stream] = current
                }
                if (direction != null) {
                    VolumeSosDetector.registerPress(this@VolumeSosService, direction)
                }
            }
        }
        contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, observer)
        volumeObserver = observer
    }
}
