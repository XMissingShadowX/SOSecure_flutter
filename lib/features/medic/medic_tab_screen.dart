import 'package:flutter/material.dart';

// Placeholder — puerto real de components/tabs/medic-tab.tsx llega en la Fase 5.
// Nota: medic-tab.tsx SÍ está conectado a Claude vía /api/chat (confirmado contra main),
// con fallback local a respuestas enlatadas si falla la red — no es un bot trivial.
// Sin Scaffold/AppBar propio — el shell provee uno solo.
class MedicTabScreen extends StatelessWidget {
  const MedicTabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Medic — Fase 5: chat con Claude vía /api/chat'));
  }
}
