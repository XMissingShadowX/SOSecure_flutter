package com.sosecure.sosecure_flutter

import android.app.NotificationManager
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Lado Activity del gesto de SOS por botón de volumen. Ya no cuenta
// pulsaciones (eso vive en VolumeSosDetector, único para toda la app) ni
// consume la tecla: solo alimenta al contador cuando la app está en primer
// plano — con la pantalla apagada las pulsaciones entran por VolumeSosService.
//
// También expone el canal de control que usa volume_button_channel.dart y
// entrega a Dart el disparo pendiente cuando la app se levanta desde el
// servicio con la app cerrada.
class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.sosecure.sosecure_flutter/volume_button"
    private val eventChannelName = "com.sosecure.sosecure_flutter/volume_button_events"
    private var listening = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyTriggerIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyTriggerIntent(intent)
    }

    // La app solo se muestra sobre la pantalla de bloqueo cuando la levantó el
    // gesto de emergencia; el resto del tiempo se comporta como cualquier app
    // (el bloqueo por PIN de la propia app sigue aplicando en ambos casos).
    private fun applyTriggerIntent(intent: Intent?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) return
        val triggered = intent?.getBooleanExtra(VolumeSosDetector.EXTRA_TRIGGER, false) == true
        setShowWhenLocked(triggered)
        setTurnScreenOn(triggered)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startListening" -> {
                        listening = true
                        VolumeSosDetector.loadConfig(this)
                        result.success(null)
                    }

                    "stopListening" -> {
                        listening = false
                        result.success(null)
                    }

                    // presses/windowMs/backgroundEnabled se persisten del lado
                    // nativo porque el servicio y el receptor de arranque los
                    // necesitan sin que haya un motor de Flutter vivo.
                    "configure" -> {
                        val presses = call.argument<Int>("presses") ?: 5
                        val windowMs = call.argument<Int>("windowMs") ?: 3000
                        val background = call.argument<Boolean>("backgroundEnabled") ?: true
                        VolumeSosDetector.configure(this, presses, windowMs, background)
                        if (background) {
                            VolumeSosService.start(this)
                        } else {
                            VolumeSosService.stop(this)
                        }
                        result.success(null)
                    }

                    "isBackgroundServiceRunning" -> result.success(VolumeSosService.running)

                    "consumePendingTrigger" ->
                        result.success(VolumeSosDetector.consumePendingTrigger(this))

                    // Android 14+ (API 34) dejó de conceder USE_FULL_SCREEN_INTENT
                    // por defecto: sin este permiso especial, wakeUpApp() en
                    // VolumeSosDetector.kt degrada a una notificación normal en vez
                    // de abrir la app sobre la pantalla de bloqueo — el disparo con
                    // el teléfono cerrado deja de "sentirse" inmediato. En versiones
                    // previas el permiso ya viene concedido, así que se reporta
                    // siempre true.
                    "canUseFullScreenIntent" -> {
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
                        } else {
                            true
                        }
                        result.success(granted)
                    }

                    "requestFullScreenIntentPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                        Uri.parse("package:$packageName"),
                                    )
                                )
                            } catch (_: Exception) {
                                // Algunos fabricantes no implementan esta pantalla de
                                // ajustes pese a declarar el API level; sin ella no hay
                                // nada más que hacer del lado nativo.
                            }
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        // Canal aparte para el tile de SOS en Ajustes Rápidos (SosTileService.kt).
        // El picker manual de "Editar Ajustes Rápidos" no lo mostraba en un
        // Cubot KingKong 9 (System UI de MediaTek muy personalizada) pese a que
        // el manifest y el registro en PackageManager son correctos — esto usa
        // la API alternativa StatusBarManager.requestAddTileService() (Android
        // 13+), que muestra un diálogo del sistema pidiéndole al usuario que
        // lo agregue directamente, sin pasar por ese picker.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sosecure.sosecure_flutter/sos_tile")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestAddTile" -> {
                        // La API vive en StatusBarManager, no en TileService —
                        // TileService.requestAddTile() no existe (verificado
                        // contra el android.jar real de compileSdk 36; el
                        // símbolo correcto es
                        // StatusBarManager.requestAddTileService()).
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val statusBarManager =
                                getSystemService(StatusBarManager::class.java)
                            statusBarManager.requestAddTileService(
                                ComponentName(this, SosTileService::class.java),
                                "SOS",
                                Icon.createWithResource(this, R.drawable.ic_tile_sos_logo),
                                mainExecutor,
                            ) { code -> result.success(code) }
                        } else {
                            // Antes de Android 13 no existe esta API — el único
                            // camino es el picker manual de Ajustes Rápidos.
                            result.success(-1)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                        VolumeSosBridge.eventSink = sink
                    }

                    override fun onCancel(arguments: Any?) {
                        VolumeSosBridge.eventSink = null
                    }
                }
            )
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (listening &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP || event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) &&
            event.action == KeyEvent.ACTION_DOWN
        ) {
            VolumeSosDetector.registerPress(
                this,
                if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down",
            )
        }
        // Se devuelve el evento al sistema (antes se consumía): con el servicio
        // en marcha los botones ya cambian el volumen con la pantalla apagada,
        // y que dentro de la app hicieran otra cosa era incoherente.
        return super.dispatchKeyEvent(event)
    }
}
