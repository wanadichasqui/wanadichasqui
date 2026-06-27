import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chasqui_service.dart';
import '../main.dart';
import 'multi_device_screen.dart';
import 'offline_sync_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nodeUrlController;
  late TextEditingController _wsUrlController;
  late TextEditingController _dummyIntervalController;
  late bool _dummyEnabled;
  late bool _darkMode;
  late String _lang;
  late bool _forceOffline;

  @override
  void initState() {
    super.initState();
    final service = Provider.of<ChasquiService>(context, listen: false);
    _nodeUrlController = TextEditingController(text: service.nodeUrl);
    _wsUrlController = TextEditingController(text: service.wsUrl);
    _dummyIntervalController = TextEditingController(text: service.dummyIntervalMs.toString());
    _dummyEnabled = service.dummyTrafficEnabled;
    _darkMode = service.isDarkMode;
    _lang = service.languageCode;
    _forceOffline = service.isForceOffline;
  }

  @override
  void dispose() {
    _nodeUrlController.dispose();
    _wsUrlController.dispose();
    _dummyIntervalController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    if (_formKey.currentState!.validate()) {
      Provider.of<ChasquiService>(context, listen: false).saveAdjustedSettings(
        node: _nodeUrlController.text.trim(),
        ws: _wsUrlController.text.trim(),
        dummyInterval: int.parse(_dummyIntervalController.text.trim()),
        dummyEnabled: _dummyEnabled,
        dark: _darkMode,
        lang: _lang,
        forceOffline: _forceOffline,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Ajustes guardados correctamente"),
          backgroundColor: WanadiBrand.safe,
        ),
      );
    }
  }

  void _showExportDialog() {
    final passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WanadiBrand.surfaceDark,
        title: const Text("Exportar Historial Cifrado", style: TextStyle(color: WanadiBrand.pureWhite)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Ingresa una contraseña para cifrar el historial local de conversaciones y contactos antes de exportarlo.",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: WanadiBrand.pureWhite),
              decoration: const InputDecoration(
                labelText: "Contraseña",
                labelStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: WanadiBrand.mintTech)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
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
              final pwd = passwordController.text.trim();
              if (pwd.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("La contraseña debe tener al menos 4 caracteres"), backgroundColor: Colors.redAccent),
                );
                return;
              }
              final service = Provider.of<ChasquiService>(context, listen: false);
              final encryptedData = service.exportEncryptedHistory(pwd);
              Navigator.pop(ctx);

              // Mostrar el código cifrado para copiar
              _showExportedDataDialog(encryptedData);
            },
            child: const Text("Exportar"),
          ),
        ],
      ),
    );
  }

  void _showExportedDataDialog(String base64Data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WanadiBrand.surfaceDark,
        title: const Text("Datos de Respaldo", style: TextStyle(color: WanadiBrand.pureWhite)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Copia este bloque de texto seguro y guárdalo en un lugar confiable:",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: WanadiBrand.navyDeep,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    base64Data,
                    style: const TextStyle(color: WanadiBrand.safe, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cerrar", style: TextStyle(color: WanadiBrand.mintTech)),
          ),
        ],
      ),
    );
  }

  void _showImportDialog() {
    final passwordController = TextEditingController();
    final dataController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WanadiBrand.surfaceDark,
        title: const Text("Importar Copia de Seguridad", style: TextStyle(color: WanadiBrand.pureWhite)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Pega el bloque de datos exportado y escribe la contraseña de cifrado correspondiente.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dataController,
                  maxLines: 4,
                  style: const TextStyle(color: WanadiBrand.safe, fontSize: 11, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: "Bloque de datos Base64",
                    labelStyle: TextStyle(color: Colors.grey),
                    border: OutlineInputBorder(borderSide: BorderSide(color: WanadiBrand.mintTech)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: const TextStyle(color: WanadiBrand.pureWhite),
                  decoration: const InputDecoration(
                    labelText: "Contraseña de cifrado",
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: WanadiBrand.mintTech)),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: WanadiBrand.safe),
            onPressed: () {
              final data = dataController.text.trim();
              final pwd = passwordController.text.trim();
              if (data.isEmpty || pwd.isEmpty) return;

              final service = Provider.of<ChasquiService>(context, listen: false);
              final success = service.importEncryptedHistory(data, pwd);
              Navigator.pop(ctx);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? "Respaldo importado correctamente" : "Fallo al importar: Datos o clave incorrectos"),
                  backgroundColor: success ? WanadiBrand.safe : Colors.redAccent,
                ),
              );
            },
            child: const Text("Importar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WanadiBrand.navyDeep,
      appBar: AppBar(
        title: const Text("Ajustes de Infraestructura", style: TextStyle(fontWeight: FontWeight.bold, color: WanadiBrand.pureWhite)),
        backgroundColor: WanadiBrand.surfaceDark,
        elevation: 4,
      ),
      body: Consumer<ChasquiService>(
        builder: (context, service, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Estado de Conexión
                  Card(
                    color: WanadiBrand.surfaceDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(
                            service.isNodeOnline ? Icons.cloud_done : Icons.cloud_off,
                            color: service.isNodeOnline ? WanadiBrand.safe : Colors.redAccent,
                            size: 32,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  service.isNodeOnline ? "Nodo Conectado (Online)" : "Nodo Desconectado (Offline)",
                                  style: const TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  service.isNodeOnline
                                      ? "Handshake Noise XX: ${service.isHandshakeComplete ? 'Activo (Canal Cifrado)' : 'Pendiente'}"
                                      : "Mensajes locales se encolarán para envío offline.",
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Configuración de red
                  const Text("RED Y SERVIDORES", style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Card(
                    color: WanadiBrand.surfaceDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nodeUrlController,
                            style: const TextStyle(color: WanadiBrand.pureWhite),
                            decoration: const InputDecoration(
                              labelText: "URL del Nodo (HTTP)",
                              labelStyle: TextStyle(color: Colors.grey),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                            ),
                            validator: (val) => val == null || val.isEmpty ? "Requerido" : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _wsUrlController,
                            style: const TextStyle(color: WanadiBrand.pureWhite),
                            decoration: const InputDecoration(
                              labelText: "URL de Señalización (WebSocket)",
                              labelStyle: TextStyle(color: Colors.grey),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                            ),
                            validator: (val) => val == null || val.isEmpty ? "Requerido" : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tráfico de Cobertura (Obfuscation)
                  const Text("SEGURIDAD Y COBERTURA", style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Card(
                    color: WanadiBrand.surfaceDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text("Tráfico de Cobertura (Dummy)", style: TextStyle(color: WanadiBrand.pureWhite)),
                            subtitle: const Text("Envía ruido periódico al mix-node para ocultar metadatos.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            value: _dummyEnabled,
                            activeColor: WanadiBrand.mintTech,
                            onChanged: (val) {
                              setState(() {
                                _dummyEnabled = val;
                              });
                            },
                          ),
                          const Divider(color: Colors.grey),
                          TextFormField(
                            controller: _dummyIntervalController,
                            style: const TextStyle(color: WanadiBrand.pureWhite),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Intervalo Dummy (milisegundos)",
                              labelStyle: TextStyle(color: Colors.grey),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) return "Requerido";
                              final n = int.tryParse(val);
                              if (n == null || n < 1000) return "Mínimo 1000ms";
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Simulación fuera de línea
                  const Text("SIMULACIÓN DE ENTORNOS TÁCTICOS", style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Card(
                    color: WanadiBrand.surfaceDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text("Forzar Modo Fuera de Línea", style: TextStyle(color: WanadiBrand.pureWhite)),
                          subtitle: const Text("Desconecta la app para probar la cola de sincronización offline.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          value: _forceOffline,
                          activeColor: Colors.orangeAccent,
                          onChanged: (val) {
                            setState(() {
                              _forceOffline = val;
                            });
                          },
                        ),
                        const Divider(color: WanadiBrand.divider, height: 1),
                        ListTile(
                          leading: const Icon(Icons.bluetooth_searching, color: WanadiBrand.mintTech),
                          title: const Text("Módulo Sin Internet", style: TextStyle(color: WanadiBrand.pureWhite)),
                          subtitle: const Text("Sincronización táctica por Bluetooth Low Energy y ZK QR.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const OfflineSyncScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Multi-dispositivo
                  const Text("MULTI-DISPOSITIVO", style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Card(
                    color: WanadiBrand.surfaceDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: const Icon(Icons.devices, color: WanadiBrand.mintTech),
                      title: const Text("Gestionar Dispositivos", style: TextStyle(color: WanadiBrand.pureWhite)),
                      subtitle: Text(
                        "${service.linkedDevices.length} dispositivo(s) vinculado(s)",
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MultiDeviceScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Respaldo de datos
                  const Text("RESPALDO Y PRIVACIDAD", style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Card(
                    color: WanadiBrand.surfaceDark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WanadiBrand.navyDeep,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _showExportDialog,
                              icon: const Icon(Icons.security, color: WanadiBrand.mintTech),
                              label: const Text("Exportar", style: TextStyle(color: WanadiBrand.pureWhite)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WanadiBrand.navyDeep,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _showImportDialog,
                              icon: const Icon(Icons.unarchive, color: WanadiBrand.safe),
                              label: const Text("Importar", style: TextStyle(color: WanadiBrand.pureWhite)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Guardar cambios
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WanadiBrand.mintTech,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _saveSettings,
                      child: const Text(
                        "Guardar Ajustes",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: WanadiBrand.pureWhite),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Logs de sistema
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("LOGS DE SISTEMA", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                      IconButton(
                        icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                        onPressed: () {
                          setState(() {
                            service.systemLogs.clear();
                          });
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: WanadiBrand.navyDeep,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade800),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: service.systemLogs.isEmpty
                        ? const Center(child: Text("Sin eventos registrados", style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: service.systemLogs.length,
                            itemBuilder: (ctx, idx) {
                              final log = service.systemLogs[idx];
                              final time = log['timestamp'] as DateTime;
                              final typeColor = log['type'] == 'error'
                                  ? Colors.redAccent
                                  : log['type'] == 'success'
                                      ? WanadiBrand.safe
                                      : log['type'] == 'cover'
                                          ? Colors.cyanAccent
                                          : Colors.grey;

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3.0),
                                child: Text(
                                  "[${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}] ${log['message']}",
                                  style: TextStyle(color: typeColor, fontSize: 11, fontFamily: 'monospace'),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
