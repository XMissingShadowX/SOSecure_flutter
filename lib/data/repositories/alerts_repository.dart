import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../domain/models/sos_alert.dart';
import '../supabase_client.dart';

// Puerto de la parte de activateSOS() en sos-button.tsx que escribe en Supabase —
// sin la porción de streaming en vivo (excluida del MVP de Flutter, ver addendum de
// plan de Fase 2 sobre streaming en vivo/emergency-chat).
class AlertsRepository {
  Future<SosAlert> createAlert({
    required double latitude,
    required double longitude,
    required List<String> contactNames,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('No autenticado');

    final data = await supabase
        .from('sos_alerts')
        .insert({
          'user_id': user.id,
          'latitude': latitude,
          'longitude': longitude,
          'status': 'active',
          'contacts_notified': contactNames,
        })
        .select()
        .single();

    final alert = SosAlert.fromJson(data);

    await supabase.from('sos_locations').insert({
      'alert_id': alert.id,
      'user_id': user.id,
      'latitude': latitude,
      'longitude': longitude,
    });

    await supabase.from('incidents').insert({
      'user_id': user.id,
      'title': 'Alerta SOS',
      'description': 'SOS de emergencia activado',
      'incident_type': 'SOS',
      'severity': 'high',
      'latitude': latitude,
      'longitude': longitude,
    });

    await _notifyContacts(alert: alert, user: user);

    return alert;
  }

  Future<void> _notifyContacts({
    required SosAlert alert,
    required User user,
  }) async {
    final contactsWithEmail =
        await supabase
                .from('emergency_contacts')
                .select('*')
                .eq('user_id', user.id)
            as List;

    if (!contactsWithEmail.any((c) => (c as Map)['email'] != null)) return;

    final token = supabase.auth.currentSession?.accessToken;
    await http.post(
      Uri.parse('${Env.supabaseUrl}/functions/v1/notify-contacts'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'alert_id': alert.id,
        'user_id': user.id,
        'user_name': user.userMetadata?['full_name'] ?? user.email,
        'latitude': alert.latitude,
        'longitude': alert.longitude,
        'contacts': contactsWithEmail,
      }),
    );
  }

  // Actualización periódica de ubicación durante SOS activo — mismo patrón que la web
  // (.update, no .upsert, porque alert_id no tiene restricción UNIQUE en sos_locations).
  Future<void> updateLocation({
    required String alertId,
    required double latitude,
    required double longitude,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase
        .from('sos_locations')
        .update({
          'latitude': latitude,
          'longitude': longitude,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('alert_id', alertId)
        .eq('user_id', user.id);
  }

  // Cancelar (falsa alarma): borra la alerta activa y el incidente reciente asociado.
  Future<void> cancelAlert() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase
        .from('sos_alerts')
        .delete()
        .eq('user_id', user.id)
        .eq('status', 'active');
    await supabase
        .from('incidents')
        .delete()
        .eq('user_id', user.id)
        .eq('title', 'Alerta SOS')
        .gte(
          'reported_at',
          DateTime.now()
              .subtract(const Duration(seconds: 60))
              .toIso8601String(),
        );
  }

  // Puerto de fetchSosHistory() en after-tab.tsx — historial de alertas propias,
  // filtrado por ventana de días (7/30/90/180, ver AfterTabScreen).
  Future<List<SosAlert>> listAlertHistory({required int days}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();
    final data =
        await supabase
                .from('sos_alerts')
                .select(
                  'id, user_id, latitude, longitude, status, contacts_notified, created_at',
                )
                .eq('user_id', user.id)
                .gte('created_at', since)
                .order('created_at', ascending: false)
            as List;
    return data
        .map((e) => SosAlert.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Marcar una alerta pasada como resuelta o falsa alarma desde el historial
  // (distinto de cancelAlert(), que borra la alerta activa en curso).
  Future<void> markAlertStatus(String alertId, String status) async {
    await supabase
        .from('sos_alerts')
        .update({'status': status})
        .eq('id', alertId);
  }
}
