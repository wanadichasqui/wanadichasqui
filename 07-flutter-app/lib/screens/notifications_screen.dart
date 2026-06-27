import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/chasqui_service.dart';
import '../main.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  Color _getLogColor(String type) {
    switch (type) {
      case 'success':
        return WanadiBrand.safe;
      case 'warning':
        return WanadiBrand.warning;
      case 'error':
        return WanadiBrand.error;
      case 'handshake':
        return Colors.purpleAccent;
      case 'cover':
        return WanadiBrand.info;
      default:
        return Colors.white70;
    }
  }

  IconData _getLogIcon(String type) {
    switch (type) {
      case 'success':
        return Icons.check_circle_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      case 'error':
        return Icons.error_outline;
      case 'handshake':
        return Icons.handshake_outlined;
      case 'cover':
        return Icons.blur_on_outlined;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<ChasquiService>(context);

    return Scaffold(
      backgroundColor: WanadiBrand.navyDeep,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "SEGURIDAD",
                        style: TextStyle(
                          color: WanadiBrand.mintTech,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Registro de Eventos",
                        style: TextStyle(
                          color: WanadiBrand.pureWhite,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, color: Colors.grey),
                    tooltip: "Limpiar registros",
                    onPressed: () {
                      service.systemLogs.clear();
                      service.logSystemEvent("Registro de eventos limpiado por el usuario.");
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: WanadiBrand.surfaceDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: WanadiBrand.divider),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: WanadiBrand.mintTech),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "Los eventos criptográficos, handshakes y auditorías del mix-node local se reportan aquí en tiempo real.",
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Log list
              Expanded(
                child: service.systemLogs.isEmpty
                    ? const Center(
                        child: Text(
                          "No hay eventos registrados.",
                          style: TextStyle(color: Colors.white24),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: service.systemLogs.length,
                        itemBuilder: (context, index) {
                          final log = service.systemLogs[index];
                          final time = log['timestamp'] as DateTime;
                          final message = log['message'] as String;
                          final type = log['type'] as String;

                          final color = _getLogColor(type);
                          final icon = _getLogIcon(type);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: WanadiBrand.surfaceDark.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: color.withOpacity(0.15),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(icon, color: color, size: 20),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            type.toUpperCase(),
                                            style: TextStyle(
                                              color: color,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                          Text(
                                            DateFormat('HH:mm:ss').format(time),
                                            style: const TextStyle(
                                              color: Colors.white24,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        message,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
