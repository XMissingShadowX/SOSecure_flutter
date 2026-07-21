import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/frequent_place.dart';

part 'places_provider.g.dart';

const _prefsKey = 'sosecure.frequentPlaces';

// Lugares frecuentes viven solo localmente — igual que en lib/store.ts (persist
// middleware de Zustand), nunca se sincronizan con Supabase.
@Riverpod(keepAlive: true)
class FrequentPlaces extends _$FrequentPlaces {
  @override
  List<FrequentPlace> build() {
    _load();
    return [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List)
        .map((e) => FrequentPlace.fromJson(e as Map<String, dynamic>))
        .toList();
    state = list;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.map((p) => p.toJson()).toList()));
  }

  void add(FrequentPlace place) {
    state = [...state, place];
    _persist();
  }

  void remove(String id) {
    state = state.where((p) => p.id != id).toList();
    _persist();
  }
}
