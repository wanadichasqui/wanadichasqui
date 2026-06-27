import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chasqui_service.dart';
import '../main.dart';

/// Pantalla para vincular y gestionar dispositivos adicionales.
/// Usa un código QR cifrado y firma de la identidad maestra.
class MultiDeviceScreen extends StatelessWidget {
  const MultiDeviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<ChasquiService>(context);

    return Scaffold(
      backgroundColor: WanadiBrand.navyDeep,
      appBar: AppBar(
        backgroundColor: WanadiBrand.surfaceDark,
        title: const Text("Multi-Dispositivo", style: TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: WanadiBrand.pureWhite),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("DISPOSITIVOS VINCULADOS", style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            const Text("Sincronización Segura", style: TextStyle(color: WanadiBrand.pureWhite, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              "Vincule dispositivos con un código QR cifrado. La identidad maestra firma las claves delegadas de cada dispositivo.",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // Dispositivo actual
            _buildDeviceCard(
              name: "Este dispositivo",
              type: "Dispositivo maestro",
              icon: Icons.phone_android,
              isMaster: true,
              isOnline: true,
              lastSeen: "Ahora",
            ),
            const SizedBox(height: 12),

            // Dispositivos vinculados simulados
            if (service.linkedDevices.isNotEmpty)
              ...service.linkedDevices.map((device) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildDeviceCard(
                  name: device['name'] as String,
                  type: "Dispositivo delegado",
                  icon: device['type'] == 'desktop' ? Icons.laptop : Icons.tablet,
                  isMaster: false,
                  isOnline: device['online'] as bool? ?? false,
                  lastSeen: device['lastSeen'] as String? ?? "Desconocido",
                ),
              )),

            const SizedBox(height: 24),

            // Vincular nuevo dispositivo
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: WanadiBrand.mintTech,
                  foregroundColor: WanadiBrand.navyDeep,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => _showLinkDeviceDialog(context, service),
                icon: const Icon(Icons.qr_code),
                label: const Text("Vincular Nuevo Dispositivo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 32),

            // Información de seguridad
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: WanadiBrand.surfaceDark,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: WanadiBrand.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: WanadiBrand.info, size: 18),
                      SizedBox(width: 8),
                      Text("CÓMO FUNCIONA", style: TextStyle(color: WanadiBrand.info, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInfoStep("1", "El dispositivo maestro genera un código QR temporal cifrado con ChaCha20."),
                  _buildInfoStep("2", "El nuevo dispositivo escanea el QR y envía su clave pública delegada."),
                  _buildInfoStep("3", "La identidad maestra firma la clave delegada (Ed25519)."),
                  _buildInfoStep("4", "Los contactos y mensajes se sincronizan cifrados E2E entre dispositivos."),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard({
    required String name,
    required String type,
    required IconData icon,
    required bool isMaster,
    required bool isOnline,
    required String lastSeen,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WanadiBrand.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMaster ? WanadiBrand.mintTech.withOpacity(0.3) : WanadiBrand.divider,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMaster
                  ? WanadiBrand.mintTech.withOpacity(0.15)
                  : WanadiBrand.navyDeep,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: isMaster ? WanadiBrand.mintTech : Colors.grey, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: const TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold, fontSize: 15)),
                    if (isMaster) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: WanadiBrand.mintTech.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text("MAESTRO", style: TextStyle(color: WanadiBrand.mintTech, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(type, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isOnline ? WanadiBrand.safe : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 4),
              Text(lastSeen, style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: WanadiBrand.mintTech.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(number, style: const TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 12, height: 1.4)),
          ),
        ],
      ),
    );
  }

  void _showLinkDeviceDialog(BuildContext context, ChasquiService service) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WanadiBrand.surfaceDark,
        title: const Text("Código de Vinculación", style: TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // QR placeholder
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: WanadiBrand.pureWhite,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Icon(Icons.qr_code_2, size: 140, color: WanadiBrand.navyDeep),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Escanee este código desde el otro dispositivo con Wanadi Chasqui instalado.",
              style: TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              "El código expira en 5 minutos.",
              style: TextStyle(color: WanadiBrand.warning, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              service.linkDevice("Desktop Linux", "desktop");
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Dispositivo vinculado exitosamente."), backgroundColor: WanadiBrand.safe),
              );
            },
            child: const Text("Simular Vinculación", style: TextStyle(color: WanadiBrand.mintTech)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cerrar", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}
