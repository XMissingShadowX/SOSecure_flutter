import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/alerts_repository.dart';
import '../domain/models/sos_alert.dart';

part 'alert_history_provider.g.dart';

@riverpod
class AlertHistoryDays extends _$AlertHistoryDays {
  @override
  int build() => 30; // '1m' por defecto, igual que sosHistoryFilter en after-tab.tsx

  void set(int days) => state = days;
}

@riverpod
class AlertHistory extends _$AlertHistory {
  final _repo = AlertsRepository();

  @override
  Future<List<SosAlert>> build() {
    final days = ref.watch(alertHistoryDaysProvider);
    return _repo.listAlertHistory(days: days);
  }

  Future<void> markStatus(String alertId, String status) async {
    await _repo.markAlertStatus(alertId, status);
    final current = state.valueOrNull ?? [];
    state = AsyncData([
      for (final a in current)
        if (a.id == alertId)
          SosAlert(
            id: a.id,
            userId: a.userId,
            latitude: a.latitude,
            longitude: a.longitude,
            status: status,
            contactsNotified: a.contactsNotified,
            createdAt: a.createdAt,
          )
        else
          a,
    ]);
  }
}
