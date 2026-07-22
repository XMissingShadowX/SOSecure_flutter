import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/repositories/recordings_repository.dart';

part 'recordings_provider.g.dart';

@riverpod
class Recordings extends _$Recordings {
  final _repo = RecordingsRepository();

  @override
  Future<List<StoredRecording>> build() => _repo.listMyRecordings();

  Future<void> delete(StoredRecording rec) async {
    await _repo.deleteRecording(rec);
    final current = state.valueOrNull ?? [];
    state = AsyncData(current.where((r) => r.id != rec.id).toList());
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.listMyRecordings());
  }
}
