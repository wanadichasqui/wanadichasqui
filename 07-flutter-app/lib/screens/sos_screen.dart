// Copyright (C) 2026 Juan Carlos Diaz Parisca / Wanadi Tactical
//
// This file is part of Wanadi Chasqui.
//
// Wanadi Chasqui is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License version 3
// as published by the Free Software Foundation.
//
// Wanadi Chasqui is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See <https://www.gnu.org/licenses/> for more details.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../services/chasqui_service.dart';
import '../services/ble_beacon_codec.dart';

/// Pantalla principal de emergencia: botón SOS gigante, estado "a salvo",
/// y lista de SOS recibidos por la mesh BLE. Diseñada para usarse en pánico,
/// poca luz y batería baja.
class SosScreen extends StatelessWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ChasquiService>();

    return Scaffold(
      backgroundColor: WanadiBrand.navyDeep,
      appBar: AppBar(
        backgroundColor: WanadiBrand.navyDeep,
        elevation: 0,
        title: const Text(
          "Emergencia",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _MeshStatusChip(active: service.meshActive),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // ── BOTÓN SOS GIGANTE ──────────────────────────────────
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SosButton(
                  onSend: () => _sendSos(context, service),
                ),
              ),
            ),
            // ── ACCIONES SECUNDARIAS ───────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _SecondaryButton(
                      label: "Necesito ayuda",
                      icon: Icons.pan_tool_alt,
                      color: WanadiBrand.warning,
                      onPressed: () => _sendHelp(context, service),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SecondaryButton(
                      label: "Estoy a salvo",
                      icon: Icons.check_circle,
                      color: WanadiBrand.safe,
                      onPressed: () => _sendSafe(context, service),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── SOS RECIBIDOS ──────────────────────────────────────
            Expanded(
              flex: 4,
              child: _ReceivedSosList(items: service.receivedSos),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendSos(BuildContext context, ChasquiService service) async {
    final messenger = ScaffoldMessenger.of(context);
    await HapticFeedback.heavyImpact();
    await service.sendSos(priority: kPriorityCritical, note: "SOS");
    _confirm(messenger, "SOS CRÍTICO emitido por la red mesh.", WanadiBrand.error);
  }

  Future<void> _sendHelp(BuildContext context, ChasquiService service) async {
    final messenger = ScaffoldMessenger.of(context);
    await HapticFeedback.mediumImpact();
    await service.sendSos(priority: kPriorityHelp, note: "Necesito ayuda");
    _confirm(messenger, "Aviso de ayuda emitido por la red mesh.", WanadiBrand.warning);
  }

  Future<void> _sendSafe(BuildContext context, ChasquiService service) async {
    final messenger = ScaffoldMessenger.of(context);
    await HapticFeedback.lightImpact();
    await service.sendSos(priority: kPrioritySafe, note: "Estoy a salvo");
    _confirm(messenger, "Estado 'estoy a salvo' emitido.", WanadiBrand.safe);
  }

  void _confirm(ScaffoldMessengerState messenger, String msg, Color color) {
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.podcasts, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SosButton extends StatelessWidget {
  final VoidCallback onSend;
  const _SosButton({required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Enviar SOS crítico por la red mesh",
      child: Material(
        color: WanadiBrand.error,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        elevation: 8,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onSend,
          child: const SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.sos_rounded, color: Colors.white, size: 96),
                SizedBox(height: 8),
                Text(
                  "SOS",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Toca para pedir auxilio",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(64),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: Icon(icon, size: 26),
        label: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _MeshStatusChip extends StatelessWidget {
  final bool active;
  const _MeshStatusChip({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? WanadiBrand.safe : WanadiBrand.error;
    return Semantics(
      label: active ? "Red mesh activa" : "Red mesh inactiva",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.podcasts : Icons.portable_wifi_off,
                color: color, size: 18),
            const SizedBox(width: 6),
            Text(
              active ? "MESH" : "OFF",
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceivedSosList extends StatelessWidget {
  final List<SosBeacon> items;
  const _ReceivedSosList({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Sin alertas SOS por ahora.\nEscuchando dispositivos cercanos…",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            "Alertas recibidas",
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _SosTile(beacon: items[i]),
          ),
        ),
      ],
    );
  }
}

class _SosTile extends StatelessWidget {
  final SosBeacon beacon;
  const _SosTile({required this.beacon});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (beacon.priority) {
      kPriorityCritical => ("SOS CRÍTICO", WanadiBrand.error, Icons.sos_rounded),
      kPriorityHelp => ("Necesita ayuda", WanadiBrand.warning, Icons.pan_tool_alt),
      _ => ("A salvo", WanadiBrand.safe, Icons.check_circle),
    };

    final loc = beacon.hasLocation
        ? "${beacon.latitude!.toStringAsFixed(5)}, ${beacon.longitude!.toStringAsFixed(5)}"
        : "Ubicación no disponible";

    return Semantics(
      label: "$label. ${beacon.note}. $loc",
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WanadiBrand.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  if (beacon.note.isNotEmpty)
                    Text(beacon.note,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15)),
                  Row(
                    children: [
                      const Icon(Icons.place, color: Colors.white54, size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(loc,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
