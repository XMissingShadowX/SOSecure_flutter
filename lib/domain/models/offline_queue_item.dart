// Puerto de `offlineQueue: Incident[]` en lib/store.ts — generalizado a
// "tabla + payload" para poder encolar tanto incidentes (map-tab, Fase 5)
// como alertas SOS fallidas (Fase 2/3), en vez de estar atado solo a Incident.
class OfflineQueueItem {
  final String table;
  final Map<String, dynamic> payload;
  final DateTime queuedAt;

  OfflineQueueItem({required this.table, required this.payload, required this.queuedAt});

  Map<String, dynamic> toJson() => {
        'table': table,
        'payload': payload,
        'queuedAt': queuedAt.toIso8601String(),
      };

  factory OfflineQueueItem.fromJson(Map<String, dynamic> json) => OfflineQueueItem(
        table: json['table'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        queuedAt: DateTime.parse(json['queuedAt'] as String),
      );
}
