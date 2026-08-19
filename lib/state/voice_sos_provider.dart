import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'sos_provider.dart';

part 'voice_sos_provider.g.dart';

const _enabledKey = 'sosecure.voiceSosEnabled';
const _keywordKey = 'sosecure.voiceKeyword';
const _defaultKeyword = 'socorro';

// Palabra que se ofrece a quien nunca configuró una propia, según el idioma
// guardado. Antes _defaultKeyword era el único valor posible: con la app en
// inglés, la tarjeta decía 'Listening: "socorro"' y la persona decía "help"
// sin que nada coincidiera nunca. Esto NO toca lo que alguien ya tenga
// guardado — solo cambia qué se ofrece a quien nunca tocó el campo.
const _defaultKeywordByLanguage = {'en': 'help'};

Future<String> _defaultKeywordForSavedLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('locale') ?? 'es';
  final languageCode = saved.split(RegExp('[_-]')).first;
  return _defaultKeywordByLanguage[languageCode] ?? _defaultKeyword;
}

// Reinicio normal tras un silencio (el reconocedor de Android corta solo).
const _restartDelay = Duration(milliseconds: 300);
// Tope del backoff cuando venimos fallando. No hay límite de reintentos: esta
// es una función de seguridad, rendirse del todo la dejaría muerta sin que
// nadie se entere. Lo que sí hay es una espera creciente hasta este máximo.
const _maxBackoffSeconds = 60;

// Android emite estos dos como "errores" durante el uso normal: el primero
// cuando no entendió nada y el segundo cuando simplemente hubo silencio.
// Tratarlos como fallas apagaría la escucha sola en una habitación callada.
const _benignErrors = {'error_no_match', 'error_speech_timeout'};

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

// Deja el texto en una forma comparable: minúsculas, sin acentos (tanto los
// precompuestos "á" como los descompuestos "a"+tilde), sin puntuación y con
// los espacios colapsados.
//
// La puntuación importa más de lo que parece: el reconocedor devuelve
// "¡Socorro!" y la palabra guardada es "socorro". Comparando en crudo contra
// un límite de palabra, esos dos NO coinciden y la alerta nunca se dispara.
String _normalize(String value) {
  const accented = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const plain = 'aaaaaeeeeiiiiooooouuuunc';
  var out = value.toLowerCase();
  for (var i = 0; i < accented.length; i++) {
    out = out.replaceAll(accented[i], plain[i]);
  }
  // Diacríticos combinantes (la forma descompuesta de las mismas vocales:
  // "a" + U+0301 en vez de "á").
  out = out.replaceAll(RegExp('[\u0300-\u036f]'), '');
  // Cualquier carácter que no sea letra o número pasa a ser separador. Se
  // aplica igual a la transcripción y a la palabra guardada, así que siguen
  // siendo comparables entre sí.
  out = out.replaceAll(RegExp('[^a-z0-9]+'), ' ');
  return out.trim();
}

// Coincidencia por palabra completa, no por substring: con `contains` una
// palabra clave corta como "ya" disparaba un SOS real al decir "playa".
// Funciona igual con claves de varias palabras ("ayuda por favor").
bool _matchesKeyword(String transcript, String keyword) {
  final normalizedKeyword = _normalize(keyword);
  if (normalizedKeyword.isEmpty) return false;
  final pattern = RegExp('(^| )${RegExp.escape(normalizedKeyword)}( |\$)');
  return pattern.hasMatch(_normalize(transcript));
}

// Google Speech no reconoce náhuatl, maya ni tseltal, así que esos caen a
// español — mismo criterio que el fallback de MaterialLocalizations en
// core/indigenous_locale_fallback.dart.
//
// Lee el idioma directo de SharedPreferences (clave 'locale') en vez de
// Intl.getCurrentLocale(). easy_localization NUNCA sincroniza
// Intl.defaultLocale (no lo asigna en ningún punto de su código fuente) —
// así que Intl.getCurrentLocale() queda pegado al locale del proceso/sistema
// sin importar qué idioma elija el usuario dentro de la app. Confirmado en
// dispositivo: con la app en español, el reconocedor seguía recibiendo
// 'en-US' porque el sistema del teléfono está en inglés — la corrección de
// locale de abajo (es_US) nunca llegaba a usarse en la práctica.
// easy_localization persiste su propio locale bajo esa clave exacta (ver
// EasyLocalizationController._saveLocale en su código fuente); como este
// Notifier no tiene BuildContext para leer context.locale, se lee la
// preferencia directo, igual que ya hace el resto de este archivo.
//
// 'es_US' y NO 'es_MX': confirmado en dispositivo (logcat, SodaLPDirGenerator
// / LanguagePackConfigImpl) que los paquetes de reconocimiento OFFLINE de
// Google solo existen para 'es-ES' y 'es-US' — 'es_MX' ni siquiera aparece
// en la lista de paquetes descargables, en ningún dispositivo. Pedirlo
// explícitamente hacía que _resolveSpeechLocale() lo encontrara como locale
// "soportado" (esa lista sí incluye es_MX, pero es la de reconocimiento por
// RED, no la de modelos offline) y se quedara con él — así que la escucha
// nunca llegaba a abrir el micrófono en cualquier escenario que cayera a
// reconocimiento local (sin red, o con la cuenta de Google fallando). De las
// dos variantes offline reales, 'es_US' es la más cercana al español
// mexicano en vocabulario (no usa "vosotros"/tuteo distinto de España).
Future<String> _preferredSpeechLocale() async {
  final prefs = await SharedPreferences.getInstance();
  // 'es' de respaldo: coincide con fallbackLocale en main.dart si el usuario
  // nunca eligió idioma a mano (SharedPreferences aún no tiene la clave).
  final saved = prefs.getString('locale') ?? 'es';
  final languageCode = saved.split(RegExp('[_-]')).first;
  return languageCode == 'en' ? 'en_US' : 'es_US';
}

@Riverpod(keepAlive: true)
class VoiceSos extends _$VoiceSos {
  final _speech = SpeechToText();
  bool _paused = false;
  bool _initialized = false;
  bool _disposed = false;
  // Evita que dos llamadas concurrentes a _listenOnce() (por ejemplo la de
  // _load() y la del listener del SOS) pasen ambas el chequeo de isListening
  // antes de que ninguna haya arrancado, y terminen llamando listen() dos veces.
  bool _starting = false;
  // Si la persona ya tocó el switch, _load() no debe pisar su decisión con el
  // valor que venía guardado en preferencias.
  bool _userSetEnabled = false;
  int _consecutiveFailures = 0;
  Timer? _restartTimer;
  // Los idiomas que el dispositivo tiene instalados (_speech.locales(), canal
  // nativo) no cambian mientras la app corre — eso sí se cachea para siempre.
  // El idioma PREFERIDO es distinto: viene de SharedPreferences y la persona
  // puede cambiarlo en Ajustes a mitad de sesión. Antes se cacheaba el
  // resultado completo de la resolución (preferido + disponibles) una sola
  // vez para siempre: alguien que abría la app en español y luego cambiaba a
  // inglés en Ajustes se quedaba con el reconocedor escuchando en español el
  // resto de la sesión, sin ningún aviso. _preferredSpeechLocale() ya es
  // barato (SharedPreferences cachea el valor en memoria tras la primera
  // lectura), así que no hace falta cachearlo aparte — se relee cada vez y
  // solo se compara contra la lista de disponibles, que esa sí es estable.
  List<LocaleName>? _cachedAvailableLocales;

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
    final saved = prefs.getString(_keywordKey);
    final keyword = saved ?? await _defaultKeywordForSavedLocale();
    if (_disposed || _userSetEnabled) return;
    state = state.copyWith(enabled: enabled, keyword: keyword);
    if (enabled) _listenOnce();
  }

  Future<void> setEnabled(bool value) async {
    _userSetEnabled = true;
    _restartTimer?.cancel();
    _consecutiveFailures = 0;
    state = state.copyWith(enabled: value, clearError: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (value) {
      _listenOnce();
    } else {
      await _speech.stop();
      if (_disposed) return;
      state = state.copyWith(listening: false);
    }
  }

  Future<void> setKeyword(String keyword) async {
    state = state.copyWith(keyword: keyword);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keywordKey, keyword);
  }

  // retry: false para fallas que no se arreglan solas (permiso denegado de
  // forma permanente). Reintentar esas solo gasta batería: hace falta que la
  // persona entre a los ajustes del sistema.
  void _fail(String message, {bool retry = true}) {
    _consecutiveFailures++;
    state = state.copyWith(errorMessage: message, listening: false);
    if (retry) _scheduleRestart();
  }

  void _onError(SpeechRecognitionError error) {
    if (_disposed) return;
    // No hubo voz que reconocer: es el caso normal, no una falla. Se deja que
    // _onStatus reinicie la escucha como siempre.
    if (_benignErrors.contains(error.errorMsg)) return;

    final message = error.errorMsg == 'error_network' ||
            error.errorMsg == 'error_network_timeout'
        ? 'voice_errorNetwork'.tr()
        : 'voice_errorGeneric'.tr();
    _fail(message);
  }

  // Usa el idioma activo de la app, pero solo si el dispositivo lo tiene
  // instalado; si no, se prefiere el idioma base y, en última instancia, se
  // devuelve null para que el reconocedor use el del sistema. Forzar un locale
  // ausente hace que la escucha falle sin explicación.
  Future<String?> _resolveSpeechLocale() async {
    final preferred = await _preferredSpeechLocale();
    // Confirmado en dispositivo: el separador de localeId puede venir con
    // guion ("es-US", como lo reporta Android en logcat) o con guion bajo
    // ("es_US", el formato que arma _preferredSpeechLocale). Comparar
    // directo contra 'es_US' fallaba SIEMPRE contra un listado en formato
    // con guion, cayendo al primer "es*" del listado (que resultó ser
    // es-ES) en vez del que en verdad se pidió.
    String normalize(String id) => id.replaceAll('-', '_');
    final normalizedPreferred = normalize(preferred);
    try {
      final available = _cachedAvailableLocales ??= await _speech.locales();
      for (final locale in available) {
        if (normalize(locale.localeId) == normalizedPreferred) {
          // Se devuelve el id tal como lo reporta el plugin, no el nuestro —
          // así se manda de vuelta exactamente en el formato que espera.
          return locale.localeId;
        }
      }
      final language = normalizedPreferred.split('_').first;
      for (final locale in available) {
        if (normalize(locale.localeId).startsWith(language)) {
          return locale.localeId;
        }
      }
      return null;
    } catch (_) {
      return preferred;
    }
  }

  Future<void> _listenOnce() async {
    if (_disposed || _paused || !state.enabled || _starting) return;
    if (_speech.isListening) return;
    _starting = true;
    try {
      await _startListening();
    } finally {
      _starting = false;
    }
  }

  Future<void> _startListening() async {
    if (!_initialized) {
      final micStatus = await Permission.microphone.request();
      if (_disposed) return;
      if (!micStatus.isGranted) {
        _fail(
          'recorder_micPermissionDenied'.tr(),
          retry: !micStatus.isPermanentlyDenied,
        );
        return;
      }
      try {
        _initialized = await _speech.initialize(
          onStatus: _onStatus,
          onError: _onError,
        );
      } catch (_) {
        _fail('voice_errorUnavailable'.tr());
        return;
      }
      if (_disposed) return;
      if (!_initialized) {
        _fail('voice_errorUnavailable'.tr());
        return;
      }
    }

    // Se vuelve a comprobar: entre el permiso y la inicialización pudo llegar
    // un SOS o el apagado del switch.
    if (_disposed || _paused || !state.enabled) return;

    try {
      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.confirmation,
          cancelOnError: false,
          // Deliberado: se actúa sobre resultados parciales para que la alerta
          // salga en cuanto se oye la palabra, sin esperar a que el reconocedor
          // cierre la frase. La coincidencia por palabra completa es la que
          // evita los falsos positivos, no el esperar al resultado final.
          partialResults: true,
          localeId: await _resolveSpeechLocale(),
        ),
      );
      if (_disposed) return;
      _consecutiveFailures = 0;
      state = state.copyWith(listening: true, clearError: true);
    } catch (_) {
      if (_disposed) return;
      _fail('voice_errorGeneric'.tr());
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
    if (_disposed || _paused || !state.enabled) return;
    _restartTimer?.cancel();
    // Backoff creciente solo cuando venimos fallando (1, 2, 4… hasta 60 s); el
    // ciclo normal de silencio -> done -> reiniciar sigue siendo inmediato.
    // Nunca deja de reintentar: una función de seguridad que se rinde sola es
    // exactamente lo que estamos tratando de evitar.
    final Duration delay;
    if (_consecutiveFailures == 0) {
      delay = _restartDelay;
    } else {
      final exponent = math.min(_consecutiveFailures - 1, 6);
      delay = Duration(
        seconds: math.min(1 << exponent, _maxBackoffSeconds),
      );
    }
    _restartTimer = Timer(delay, () {
      if (!_disposed) _listenOnce();
    });
  }
}
