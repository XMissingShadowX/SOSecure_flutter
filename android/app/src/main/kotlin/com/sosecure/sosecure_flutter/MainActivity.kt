package com.sosecure.sosecure_flutter

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Puerto de VolumeButtonPlugin.java (Capacitor) — mismo contrato (escuchar
// solo mientras `listening` es true, consumir el evento para que el sistema
// no cambie el volumen real). El debounce de 5 pulsaciones/3s vive en Dart
// (volume_sos_provider.dart), aquí solo se reenvía cada evento crudo.
class MainActivity : FlutterActivity() {
    private val methodChannelName = "com.sosecure.sosecure_flutter/volume_button"
    private val eventChannelName = "com.sosecure.sosecure_flutter/volume_button_events"
    private var listening = false
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> { listening = true; result.success(null) }
                "stopListening" -> { listening = false; result.success(null) }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { eventSink = sink }
                override fun onCancel(arguments: Any?) { eventSink = null }
            }
        )
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (listening &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP || event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) &&
            event.action == KeyEvent.ACTION_DOWN
        ) {
            val button = if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
            eventSink?.success(mapOf("button" to button, "timestamp" to System.currentTimeMillis()))
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
