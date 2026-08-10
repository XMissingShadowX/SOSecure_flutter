package com.sosecure.sosecure_flutter

import android.content.Intent
import android.os.Build
import android.os.Bundle
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
