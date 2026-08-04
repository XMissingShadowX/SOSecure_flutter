import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'sos_provider.dart';

part 'voice_sos_provider.g.dart';

const _enabledKey = 'sosecure.voiceSosEnabled';
const _keywordKey = 'sosecure.voiceKeyword';
const _defaultKeyword = 'socorro';

class VoiceSosState {
  final bool enabled;
  final String keyword;
  final bool listening;
  final String? errorMessage;

  const VoiceSosState({
    this.enabled = false,
    this.keyword = _defaultKeyword,
    this.listening = false,
    this.errorMessage,
  });

  VoiceSosState copyWith({
    bool? enabled,
    String? keyword,
    bool? listening,
    String? errorMessage,
  }) {
    return VoiceSosState(
      enabled: enabled ?? this.enabled,
      keyword: keyword ?? this.keyword,
      listening: listening ?? this.listening,
      errorMessage: errorMessage,
    );
  }
}

// Puerto del reconocimiento de voz continuo de app-shell.tsx (Web Speech API)
// usando `speech_to_text` en Android nativo. A diferencia del navegador (que
// mantiene un solo listener "continuous"), el SpeechRecognizer de Android
// corta el reconocimiento tras un silencio corto — por eso `_onStatus`
// reinicia el listener automáticamente en vez de asumir continuidad real,
// espeando el patrón onend->restart de la web.
//
// El campo `_paused` (equivalente a voicePausedRef en app-shell.tsx) se
// actualiza de forma síncrona al escuchar sosProvider — no hay problema de
// stale closures en Dart como en React, así que no hace falta una ref aparte.
@Riverpod(keepAlive: true)
class VoiceSos extends _$VoiceSos {
  final _speech = SpeechToText();
  bool _paused = false;
  bool _initialized = false;

  @override
  VoiceSosState build() {
    _load();
    ref.listen(sosProvider, (prev, next) {
      _paused = next.active;
      if (_paused) {
        _speech.stop();
      } else if (state.enabled) {
        _listenOnce();
      }
    });
    ref.onDispose(() => _speech.stop());
    return const VoiceSosState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    final keyword = prefs.getString(_keywordKey) ?? _defaultKeyword;
    state = state.copyWith(enabled: enabled, keyword: keyword);
    if (enabled) _listenOnce();
  }

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value, errorMessage: '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (value) {
      _listenOnce();
    } else {
      await _speech.stop();
      state = state.copyWith(listening: false);
    }
  }

  Future<void> setKeyword(String keyword) async {
    state = state.copyWith(keyword: keyword);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keywordKey, keyword);
  }

  Future<void> _listenOnce() async {
    if (_paused || !state.enabled) return;

    if (!_initialized) {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        state = state.copyWith(
          errorMessage: 'Permiso de micrófono denegado.',
          listening: false,
        );
        return;
      }
      try {
        _initialized = await _speech.initialize(
          onStatus: _onStatus,
          onError: (e) => state = state.copyWith(
            errorMessage: e.errorMsg,
            listening: false,
          ),
        );
      } catch (e) {
        state = state.copyWith(
          errorMessage:
              'Reconocimiento de voz no disponible en este dispositivo (servicio de Google Speech no instalado/soportado).',
          listening: false,
        );
        return;
      }
      if (!_initialized) {
        state = state.copyWith(
          errorMessage:
              'Reconocimiento de voz no disponible en este dispositivo.',
          listening: false,
        );
        return;
      }
    }

    if (_speech.isListening) return;
    try {
      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.confirmation,
          cancelOnError: false,
          localeId: 'es_MX',
        ),
      );
      state = state.copyWith(listening: true, errorMessage: '');
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'No se pudo iniciar la escucha: $e',
        listening: false,
      );
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (_paused) return;
    final transcript = result.recognizedWords.toLowerCase();
    if (transcript.isNotEmpty && transcript.contains(state.keyword)) {
      ref.read(sosProvider.notifier).activate();
    }
  }

  // El reconocedor de Android corta la escucha tras un silencio — se reinicia
  // aquí, igual que el onend->start() de la web (solo si sigue habilitado y
  // no está pausado por un SOS activo).
  void _onStatus(String status) {
    state = state.copyWith(listening: status == 'listening');
    if ((status == 'done' || status == 'notListening') &&
        state.enabled &&
        !_paused) {
      Future.delayed(const Duration(milliseconds: 300), _listenOnce);
    }
  }
}
