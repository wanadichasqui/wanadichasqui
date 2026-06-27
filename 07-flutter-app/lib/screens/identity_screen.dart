import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/chasqui_service.dart';
import '../main.dart';
import 'offline_sync_screen.dart';

class IdentityScreen extends StatefulWidget {
  const IdentityScreen({super.key});

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mnemonicImportController = TextEditingController();
  bool _isEditingName = false;

  @override
  void initState() {
    super.initState();
    final service = Provider.of<ChasquiService>(context, listen: false);
    _nameController.text = service.displayName;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mnemonicImportController.dispose();
    super.dispose();
  }

  void _showImportMnemonicDialog(BuildContext context, ChasquiService service) {
    _mnemonicImportController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WanadiBrand.surfaceDark,
        title: const Text(
          "Importar desde Frase",
          style: TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Pegue su frase de recuperación de 12 palabras separadas por espacios:",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _mnemonicImportController,
              maxLines: 3,
              style: const TextStyle(color: WanadiBrand.pureWhite, fontSize: 14),
              decoration: InputDecoration(
                hintText: "ej. tactical soberania chasqui...",
                hintStyle: const TextStyle(color: Colors.white24),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: WanadiBrand.mintTech.withOpacity(0.3)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: WanadiBrand.mintTech),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: WanadiBrand.mintTech,
              foregroundColor: WanadiBrand.navyDeep,
            ),
            onPressed: () {
              final text = _mnemonicImportController.text.trim();
              if (text.split(RegExp(r'\s+')).length == 12) {
                service.importFromMnemonic(text);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Identidad importada con éxito."),
                    backgroundColor: WanadiBrand.safe,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("La frase debe tener exactamente 12 palabras."),
                    backgroundColor: WanadiBrand.error,
                  ),
                );
              }
            },
            child: const Text("Importar"),
          ),
        ],
      ),
    );
  }

  void _showExportBackupDialog(BuildContext context, ChasquiService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WanadiBrand.surfaceDark,
        title: const Text(
          "Exportar Respaldo",
          style: TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.archive_outlined, color: WanadiBrand.mintTech, size: 48),
            SizedBox(height: 12),
            Text(
              "Se exportará un archivo de base de datos cifrado `chasqui_vault.backup` de forma portátil a la carpeta de descargas del dispositivo.",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            SizedBox(height: 8),
            Text(
              "Nota: Este respaldo se cifra con la clave maestra derivada de su sesión.",
              style: TextStyle(color: Colors.white30, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: WanadiBrand.mintTech,
              foregroundColor: WanadiBrand.navyDeep,
            ),
            onPressed: () {
              Navigator.pop(context);
              service.logSystemEvent("Respaldo exportado correctamente (storage_export simulado).", type: "success");
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Respaldo exportado correctamente."),
                  backgroundColor: WanadiBrand.safe,
                ),
              );
            },
            child: const Text("Exportar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<ChasquiService>(context);
    final pubKeyFormatted = "ed25519:${service.localPublicKeyHex ?? ''}";

    return Scaffold(
      backgroundColor: WanadiBrand.navyDeep,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
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
                        "IDENTIDAD NODAL",
                        style: TextStyle(
                          color: WanadiBrand.mintTech,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Mi Perfil Criptográfico",
                        style: TextStyle(
                          color: WanadiBrand.pureWhite,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: service.isForceOffline
                          ? const Color(0xFFE5484D).withOpacity(0.1)
                          : service.isNodeOnline
                              ? WanadiBrand.safe.withOpacity(0.1)
                              : WanadiBrand.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: service.isForceOffline
                            ? const Color(0xFFE5484D)
                            : service.isNodeOnline
                                ? WanadiBrand.safe
                                : WanadiBrand.warning,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: service.isForceOffline
                                ? const Color(0xFFE5484D)
                                : service.isNodeOnline
                                    ? WanadiBrand.safe
                                    : WanadiBrand.warning,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          service.isForceOffline
                              ? "SIN INTERNET"
                              : service.isNodeOnline
                                  ? "ONLINE"
                                  : "DEMO",
                          style: TextStyle(
                            color: service.isForceOffline
                                ? const Color(0xFFE5484D)
                                : service.isNodeOnline
                                    ? WanadiBrand.safe
                                    : WanadiBrand.warning,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Avatar & Name Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: WanadiBrand.surfaceDark,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: WanadiBrand.divider),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [WanadiBrand.mintTech, WanadiBrand.info],
                        ),
                      ),
                      child: const CircleAvatar(
                        radius: 40,
                        backgroundColor: WanadiBrand.navyDeep,
                        child: Icon(
                          Icons.security,
                          size: 40,
                          color: WanadiBrand.mintTech,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _isEditingName
                            ? SizedBox(
                                width: 180,
                                child: TextField(
                                  controller: _nameController,
                                  style: const TextStyle(
                                    color: WanadiBrand.pureWhite,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                  decoration: const InputDecoration(
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(color: WanadiBrand.mintTech),
                                    ),
                                  ),
                                ),
                              )
                            : Text(
                                service.displayName,
                                style: const TextStyle(
                                  color: WanadiBrand.pureWhite,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                        IconButton(
                          icon: Icon(
                            _isEditingName ? Icons.check : Icons.edit,
                            color: Colors.grey,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              if (_isEditingName) {
                                service.updateDisplayName(_nameController.text);
                              }
                              _isEditingName = !_isEditingName;
                            });
                          },
                        ),
                      ],
                    ),
                    const Text(
                      "Identidad Soberana Activa",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Public Key Hex Card
              const Text(
                "CLAVE PÚBLICA",
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: WanadiBrand.surfaceDark.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: WanadiBrand.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Dirección de Red",
                          style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: Colors.grey, size: 18),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: pubKeyFormatted));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Clave pública copiada al portapapeles."),
                                backgroundColor: WanadiBrand.safe,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    Text(
                      pubKeyFormatted,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 12-Word Mnemonic Phrase Card
              const Text(
                "FRASE DE RECUPERACIÓN (12 PALABRAS)",
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: WanadiBrand.surfaceDark.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: WanadiBrand.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_outlined, color: WanadiBrand.warning, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          "Escríbala y guárdela en un lugar seguro",
                          style: TextStyle(color: WanadiBrand.warning, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      service.localMnemonic ?? "No generada",
                      style: const TextStyle(
                        color: WanadiBrand.pureWhite,
                        fontSize: 14,
                        letterSpacing: 0.5,
                        height: 1.6,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            if (service.localMnemonic != null) {
                              Clipboard.setData(ClipboardData(text: service.localMnemonic!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Frase mnemónica copiada."),
                                  backgroundColor: WanadiBrand.safe,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy, size: 14, color: WanadiBrand.mintTech),
                          label: const Text("Copiar frase", style: TextStyle(color: WanadiBrand.mintTech, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: WanadiBrand.mintTech.withOpacity(0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => _showImportMnemonicDialog(context, service),
                      icon: const Icon(Icons.vpn_key_outlined, color: WanadiBrand.mintTech, size: 18),
                      label: const Text("Importar Frase", style: TextStyle(color: WanadiBrand.mintTech, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: WanadiBrand.mintTech.withOpacity(0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => _showExportBackupDialog(context, service),
                      icon: const Icon(Icons.download_for_offline_outlined, color: WanadiBrand.mintTech, size: 18),
                      label: const Text("Respaldar BD", style: TextStyle(color: WanadiBrand.mintTech, fontSize: 13)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Módulo Sin Internet / Conexión Táctica
              Card(
                color: WanadiBrand.surfaceDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE5484D), width: 1),
                ),
                child: ListTile(
                  leading: const Icon(Icons.emergency_share, color: Color(0xFFE5484D)),
                  title: const Text(
                    "Módulo Sin Internet (BLE)",
                    style: TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: const Text(
                    "Sincronización táctica y comunicación de emergencia.",
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OfflineSyncScreen()),
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
