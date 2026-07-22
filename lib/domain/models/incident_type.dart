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
const Map<IncidentType, List<String>> incidentQuestions = {
  IncidentType.theftAssaultViolence: [
    '¿El agresor tenía un arma?',
    '¿Hubo violencia física?',
    '¿Hay alguien herido?',
  ],
  IncidentType.harassmentSuspicious: [
    '¿Te está siguiendo?',
    '¿Hubo amenazas?',
    '¿Hay alguien en situación vulnerable?',
  ],
  IncidentType.accident: [
    '¿Hay heridos?',
    '¿Hay fuego?',
    '¿Está bloqueando el paso?',
  ],
};

// 'si' = 1, 'no_se' = 0.5, 'no' = 0 — idéntico a calculateSeverity() de la web.
IncidentSeverity calculateSeverity(List<String> answers) {
  final score = answers.fold<double>(0, (sum, a) => sum + (a == 'si' ? 1 : a == 'no_se' ? 0.5 : 0));
  if (score >= 3) return 'high';
  if (score == 0) return 'low';
  return 'medium';
}
