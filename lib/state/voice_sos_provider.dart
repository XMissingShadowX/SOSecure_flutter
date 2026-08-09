import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
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

// Reinicio normal tras un silencio (el reconocedor de Android corta solo).
const _restartDelay = Duration(milliseconds: 300);
// Tras este número de fallos seguidos se deja de reintentar y se deja el error
// visible: reintentar cada 300 ms sin servicio de voz solo drena la batería.
const _maxConsecutiveFailures = 5;

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
    // Limpiar el error tiene que ser explícito. Antes `errorMessage` se asignaba
    // directo (sin `?? this.errorMessage`), así que cualquier copyWith que no lo
    // pasara — por ejemplo el de _onStatus, que corre en cada cambio de estado —
    // borraba el error a los milisegundos y el usuario nunca alcanzaba a verlo.
    bool clearError = false,
  }) {
    return VoiceSosState(
      enabled: enabled ?? this.enabled,
      keyword: keyword ?? this.keyword,
      listening: listening ?? this.listening,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// Quita acentos y normaliza a minúsculas. El reconocedor devuelve el texto
// acentuado ("ayúdame") mientras que la palabra guardada casi nunca lo está
// ("ayudame"); sin normalizar ambos lados, el SOS por voz nunca se dispara.
String _normalize(String value) {
  const accented = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const plain = 'aaaaaeeeeiiiiooooouuuunc';
  var out = value.toLowerCase().trim();
  for (var i = 0; i < accented.length; i++) {
    out = out.replaceAll(accented[i], plain[i]);
  }
  return out;
}

// Coincidencia por palabra completa, no por substring: con `contains` una
// palabra clave corta como "ya" disparaba un SOS real al decir "playa".
bool _matchesKeyword(String transcript, String keyword) {
  final normalizedKeyword = _normalize(keyword);
  if (normalizedKeyword.isEmpty) return false;
  final pattern = RegExp(
    '(^|\\s)${RegExp.escape(normalizedKeyword)}(\\s|\$)',
  );
  return pattern.hasMatch(_normalize(transcript));
}

// Google Speech no reconoce náhuatl, maya ni tseltal, así que esos caen a
// español — mismo criterio que el fallback de MaterialLocalizations en
// core/indigenous_locale_fallback.dart.
String _speechLocaleId() {
  final languageCode = Intl.getCurrentLocale().split(RegExp('[_-]')).first;
  return languageCode == 'en' ? 'en_US' : 'es_MX';
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
  bool _disposed = false;
  int _consecutiveFailures = 0;
  Timer? _restartTimer;

  @override
  VoiceSosState build() {
    // ref.listen solo avisa de cambios POSTERIORES: si el provider se construye
    // con un SOS ya activo, sin esta lectura inicial _paused quedaría en false
    // y arrancaríamos a escuchar en plena emergencia.
    _paused = ref.read(sosProvider).active;
    _load();
    ref.listen(sosProvider, (prev, next) {
      _paused = next.active;
      if (_paused) {
        _restartTimer?.cancel();
        _speech.stop();
      } else if (state.enabled) {
        _consecutiveFailures = 0;
        _listenOnce();
      }
    });
    ref.onDispose(() {
      _disposed = true;
      _restartTimer?.cancel();
      _speech.stop();
    });
    return const VoiceSosState();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    final keyword = prefs.getString(_keywordKey) ?? _defaultKeyword;
    if (_disposed) return;
    state = state.copyWith(enabled: enabled, keyword: keyword);
    if (enabled) _listenOnce();
  }

  Future<void> setEnabled(bool value) async {
    _restartTimer?.cancel();
    _consecutiveFailures = 0;
    state = state.copyWith(enabled: value, clearError: true);
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

  void _fail(String message) {
    _consecutiveFailures++;
    state = state.copyWith(errorMessage: message, listening: false);
  }

  Future<void> _listenOnce() async {
    if (_disposed || _paused || !state.enabled) return;

    if (!_initialized) {
      final micStatus = await Permission.microphone.request();
      if (_disposed) return;
      if (!micStatus.isGranted) {
        _fail('recorder_micPermissionDenied'.tr());
        return;
      }
      try {
        _initialized = await _speech.initialize(
          onStatus: _onStatus,
          onError: (e) => _fail(e.errorMsg),
        );
      } catch (_) {
        _fail(
          'Reconocimiento de voz no disponible en este dispositivo (servicio de Google Speech no instalado/soportado).',
        );
        return;
      }
      if (_disposed) return;
      if (!_initialized) {
        _fail('Reconocimiento de voz no disponible en este dispositivo.');
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
          localeId: _speechLocaleId(),
        ),
      );
      if (_disposed) return;
      _consecutiveFailures = 0;
      state = state.copyWith(listening: true, clearError: true);
    } catch (e) {
      if (_disposed) return;
      _fail('No se pudo iniciar la escucha: $e');
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (_disposed || _paused) return;
    if (_matchesKeyword(result.recognizedWords, state.keyword)) {
      ref.read(sosProvider.notifier).activate();
    }
  }

  // El reconocedor de Android corta la escucha tras un silencio — se reinicia
  // aquí, igual que el onend->start() de la web (solo si sigue habilitado y
  // no está pausado por un SOS activo).
  void _onStatus(String status) {
    if (_disposed) return;
    state = state.copyWith(listening: status == 'listening');
    if ((status == 'done' || status == 'notListening') &&
        state.enabled &&
        !_paused) {
      _scheduleRestart();
    }
  }

  void _scheduleRestart() {
    if (_consecutiveFailures >= _maxConsecutiveFailures) return;
    _restartTimer?.cancel();
    // Backoff exponencial solo cuando venimos fallando: el ciclo normal
    // (silencio -> done -> reiniciar) sigue siendo inmediato.
    final delay = _consecutiveFailures == 0
        ? _restartDelay
        : Duration(seconds: 1 << (_consecutiveFailures - 1));
    _restartTimer = Timer(delay, () {
      if (!_disposed) _listenOnce();
    });
  }
}
