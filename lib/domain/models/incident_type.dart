import 'package:easy_localization/easy_localization.dart';

// Espeja IncidentType/IncidentSeverity en lib/types.ts. Estos valores viajan
// tal cual a la BD — nunca se traducen (ver CLAUDE.md, "Strings que NO se
// traducen"), solo la UI los muestra localizados.
enum IncidentType {
  theftAssaultViolence('theft-assault-violence'),
  harassmentSuspicious('harassment-suspicious'),
  accident('accident'),
  sos('SOS');

  final String value;
  const IncidentType(this.value);
}

typedef IncidentSeverity = String; // 'high' | 'medium' | 'low'

// Puerto de incidentQuestionKeys + calculateSeverity() en during-tab.tsx.
// Getter (no const) porque .tr() no es una expresión constante — llamarlo a
// nivel de módulo/const congelaría las preguntas en el idioma de compilación.
Map<IncidentType, List<String>> get incidentQuestions => {
  IncidentType.theftAssaultViolence: [
    'during_q_weapon'.tr(),
    'during_q_violence'.tr(),
    'during_q_injured'.tr(),
  ],
  IncidentType.harassmentSuspicious: [
    'during_q_following'.tr(),
    'during_q_threats'.tr(),
    'during_q_vulnerable'.tr(),
  ],
  IncidentType.accident: [
    'during_q_injuredAcc'.tr(),
    'during_q_fire'.tr(),
    'during_q_blocked'.tr(),
  ],
};

// 'si' = 1, 'no_se' = 0.5, 'no' = 0 — idéntico a calculateSeverity() de la web.
IncidentSeverity calculateSeverity(List<String> answers) {
  final score = answers.fold<double>(
    0,
    (sum, a) =>
        sum +
        (a == 'si'
            ? 1
            : a == 'no_se'
            ? 0.5
            : 0),
  );
  if (score >= 3) return 'high';
  if (score == 0) return 'low';
  return 'medium';
}
