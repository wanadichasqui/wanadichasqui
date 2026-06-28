import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/chasqui_service.dart';
import '../main.dart';

class OfflineSyncScreen extends StatefulWidget {
  const OfflineSyncScreen({super.key});

  @override
  State<OfflineSyncScreen> createState() => _OfflineSyncScreenState();
}

class _OfflineSyncScreenState extends State<OfflineSyncScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final TextEditingController _qrInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _qrInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<ChasquiService>(context);

    return Scaffold(
      backgroundColor: WanadiBrand.navyDeep,
      appBar: AppBar(
        backgroundColor: WanadiBrand.surfaceDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: WanadiBrand.mintTech),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Módulo Sin Internet",
              style: TextStyle(color: WanadiBrand.pureWhite, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              "Sincronización Táctica BLE / Mesh",
              style: TextStyle(color: WanadiBrand.mintTech.withOpacity(0.8), fontSize: 11),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- ALERTA DE CATÁSTROFE / MODO DE EMERGENCIA ---
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE5484D), Color(0xFF900C0F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE5484D).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 36),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "COMUNICACIÓN DE EMERGENCIA CIVIL",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Modo táctico activado. Permite intercambiar mensajes cifrados de extremo a extremo sin conexión a Internet utilizando saltos físicos entre dispositivos (BLE/Mesh).",
                            style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- CONTROL DE MODO SIN INTERNET ---
              const Text(
                "ESTADO GLOBAL",
                style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5),
              ),
              const SizedBox(height: 8),
              Card(
                color: WanadiBrand.surfaceDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: SwitchListTile(
                  title: const Text(
                    "Forzar Modo Sin Internet",
                    style: TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: const Text(
                    "Simula una desconexión total para probar la cola de sincronización táctica local.",
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  value: service.isForceOffline,
                  activeColor: WanadiBrand.mintTech,
                  onChanged: (val) {
                    HapticFeedback.heavyImpact();
                service.toggleOfflineMode(forceOffline: val);
                  },
                ),
              ),
              const SizedBox(height: 20),

              // --- COLA DE MENSAJES PENDIENTES ---
              const Text(
                "BUZÓN TÁCTICO LOCAL",
                style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5),
              ),
              const SizedBox(height: 8),
              Card(
                color: WanadiBrand.surfaceDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: WanadiBrand.navyDeep,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.mail_outline,
                          color: service.offlineQueue.isNotEmpty ? const Color(0xFFF5B942) : WanadiBrand.mintTech,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${service.offlineQueue.length} Mensaje(s) Encolado(s)",
                              style: const TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              service.offlineQueue.isEmpty
                                  ? "Todos tus mensajes han sido entregados."
                                  : "Esperando un salto BLE o reconexión a internet para entregar.",
                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // --- TRANSMISIÓN Y ESCANEO BLE ---
              const Text(
                "RADIO TÁCTICO (BLUETOOTH LOW ENERGY)",
                style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildActionButton(
                      title: "Transmitir (Beacon)",
                      subtitle: service.isBleAdvertising ? "Anunciando..." : "Inactivo",
                      icon: Icons.wifi_tethering,
                      isActive: service.isBleAdvertising,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        if (service.isBleAdvertising) {
                          service.stopBleAdvertising();
                        } else {
                          service.startBleAdvertising();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildActionButton(
                      title: "Escanear Pares",
                      subtitle: service.isBleScanning ? "Buscando..." : "Inactivo",
                      icon: Icons.bluetooth_searching,
                      isActive: service.isBleScanning,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        if (service.isBleScanning) {
                          service.stopBleScanning();
                        } else {
                          service.startBleScanning();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // --- LISTA DE DISPOSITIVOS DETECTADOS ---
              if (service.isBleScanning) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "DISPOSITIVOS DETECTADOS",
                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: WanadiBrand.mintTech.withOpacity(_pulseController.value),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (service.detectedBlePeers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32.0),
                    child: Center(
                      child: Text(
                        "Buscando señales... Asegúrate de que otros nodos estén transmitiendo.",
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: service.detectedBlePeers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final peer = service.detectedBlePeers[index];
                      final isSynced = peer['synced'] == true;
                      final int rssi = (peer['rssi'] as num?)?.toInt() ?? -90;
                      final Color rssiColor = rssi > -60
                          ? const Color(0xFF00E676)
                          : rssi > -80
                              ? Colors.orangeAccent
                              : Colors.redAccent;
                      final int bars = rssi > -60 ? 4 : rssi > -70 ? 3 : rssi > -80 ? 2 : 1;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF071424),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: rssiColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.router_rounded, color: rssiColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    peer['name']?.toString().isEmpty == true ? "Nodo Anónimo" : peer['name'].toString(),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "ID: ${peer['id'].toString().substring(0, 8)}... | ${peer['device'] ?? 'BLE'}",
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  "$rssi dBm",
                                  style: TextStyle(color: rssiColor, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: List.generate(4, (i) {
                                    return Container(
                                      width: 3,
                                      height: (i + 1) * 3.0,
                                      margin: const EdgeInsets.only(left: 1.5),
                                      decoration: BoxDecoration(
                                        color: i < bars ? rssiColor : Colors.white10,
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                    );
                                  }),
                                ),
                                const SizedBox(height: 6),
                                isSynced
                                  ? const Icon(Icons.check_circle, color: WanadiBrand.safe, size: 20)
                                  : GestureDetector(
                                      onTap: () => _handlePeerSync(context, service, peer),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: WanadiBrand.navyDeep,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: WanadiBrand.mintTech.withOpacity(0.5)),
                                        ),
                                        child: const Text(
                                          "Sincronizar",
                                          style: TextStyle(color: WanadiBrand.mintTech, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 16),
              ],

              // --- BUZÓN QR / INVITACIÓN ZK ---
              const Text(
                "BUZONES FÍSICOS Y TRANSFERENCIA QR",
                style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5),
              ),
              const SizedBox(height: 8),
              Card(
                color: WanadiBrand.surfaceDark,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: WanadiBrand.mintTech),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () => _showQRInviteDialog(context, service),
                              icon: const Icon(Icons.qr_code_2, color: WanadiBrand.mintTech),
                              label: const Text("Mostrar Invitación ZK", style: TextStyle(color: WanadiBrand.pureWhite, fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WanadiBrand.mintTech,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () => _showScanDialog(context, service),
                              icon: const Icon(Icons.qr_code_scanner, color: WanadiBrand.pureWhite),
                              label: const Text("Importar Código ZK", style: TextStyle(color: WanadiBrand.pureWhite, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(minHeight: 120),
        decoration: BoxDecoration(
          color: isActive ? WanadiBrand.mintTech.withOpacity(0.15) : WanadiBrand.surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? WanadiBrand.mintTech : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(
              icon,
              color: isActive ? WanadiBrand.mintTech : Colors.white54,
              size: 28,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: isActive ? WanadiBrand.mintTech : Colors.white38,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handlePeerSync(BuildContext context, ChasquiService service, Map<String, dynamic> peer) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          color: WanadiBrand.surfaceDark,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: WanadiBrand.mintTech),
                const SizedBox(height: 16),
                Text(
                  "Sincronizando con ${peer['name']}...",
                  style: const TextStyle(color: WanadiBrand.pureWhite),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Intercambiando fragmentos cifrados de red local...",
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await service.syncOfflineQueueWithPeer(peer['id']);

    if (context.mounted) {
      Navigator.pop(context); // Cerrar loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Sincronización finalizada con ${peer['name']}"),
          backgroundColor: WanadiBrand.safe,
        ),
      );
    }
  }

  void _showQRInviteDialog(BuildContext context, ChasquiService service) {
    final inviteToken = service.generateOfflineInvitation();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WanadiBrand.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Invitación Ciega ZK", style: TextStyle(color: WanadiBrand.pureWhite)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Permite que otro dispositivo escanee este código para vincularse de forma segura sin revelar tu identidad.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 20),
            // Simular un QR Code con diseño abstracto premium
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: CustomPaint(
                painter: QRPlaceholderPainter(),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              inviteToken,
              textAlign: TextAlign.center,
              style: const TextStyle(color: WanadiBrand.mintTech, fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cerrar", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _showScanDialog(BuildContext context, ChasquiService service) {
    _qrInputController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WanadiBrand.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Importar Código ZK", style: TextStyle(color: WanadiBrand.pureWhite)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Ingresa la frase del token ZK de invitación o el contenido escaneado para importar:",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qrInputController,
              style: const TextStyle(color: WanadiBrand.pureWhite, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Ej: WNAD-ZK-INVITE-...",
                hintStyle: const TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade800),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: WanadiBrand.mintTech),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: WanadiBrand.mintTech),
            onPressed: () {
              final val = _qrInputController.text.trim();
              if (val.isNotEmpty) {
                service.importOfflineData(val);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Código importado exitosamente"),
                    backgroundColor: WanadiBrand.safe,
                  ),
                );
              }
            },
            child: const Text("Importar", style: TextStyle(color: WanadiBrand.pureWhite)),
          ),
        ],
      ),
    );
  }
}

class QRPlaceholderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = WanadiBrand.navyDeep
      ..style = PaintingStyle.fill;

    // Pintar los 3 cuadrados de las esquinas (marcadores de posición QR estándar)
    double markerSize = 40;
    
    // Top Left
    canvas.drawRect(Rect.fromLTWH(0, 0, markerSize, markerSize), paint);
    canvas.drawRect(Rect.fromLTWH(4, 4, markerSize - 8, markerSize - 8), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(10, 10, markerSize - 20, markerSize - 20), paint);

    // Top Right
    canvas.drawRect(Rect.fromLTWH(size.width - markerSize, 0, markerSize, markerSize), paint);
    canvas.drawRect(Rect.fromLTWH(size.width - markerSize + 4, 4, markerSize - 8, markerSize - 8), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(size.width - markerSize + 10, 10, markerSize - 20, markerSize - 20), paint);

    // Bottom Left
    canvas.drawRect(Rect.fromLTWH(0, size.height - markerSize, markerSize, markerSize), paint);
    canvas.drawRect(Rect.fromLTWH(4, size.height - markerSize + 4, markerSize - 8, markerSize - 8), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromLTWH(10, size.height - markerSize + 10, markerSize - 20, markerSize - 20), paint);

    // Pintar unos bloques abstractos simulando el contenido del código QR
    final randomPaint = Paint()..color = WanadiBrand.navyDeep.withOpacity(0.85);
    canvas.drawRect(Rect.fromLTWH(50, 10, 15, 15), randomPaint);
    canvas.drawRect(Rect.fromLTWH(75, 20, 10, 25), randomPaint);
    canvas.drawRect(Rect.fromLTWH(50, 50, 25, 10), randomPaint);
    canvas.drawRect(Rect.fromLTWH(10, 55, 15, 30), randomPaint);
    canvas.drawRect(Rect.fromLTWH(40, 75, 40, 15), randomPaint);
    canvas.drawRect(Rect.fromLTWH(95, 50, 30, 30), randomPaint);
    
    canvas.drawRect(Rect.fromLTWH(10, 95, 20, 15), randomPaint);
    canvas.drawRect(Rect.fromLTWH(45, 100, 15, 45), randomPaint);
    canvas.drawRect(Rect.fromLTWH(75, 110, 35, 15), randomPaint);
    canvas.drawRect(Rect.fromLTWH(size.width - 50, 95, 40, 20), randomPaint);
    
    canvas.drawRect(Rect.fromLTWH(110, 10, 20, 30), randomPaint);
    canvas.drawRect(Rect.fromLTWH(115, 130, 30, 20), randomPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
