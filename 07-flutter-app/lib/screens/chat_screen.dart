import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../services/chasqui_service.dart';
import '../main.dart';


class ChatScreen extends StatefulWidget {
  final Contact contact;

  const ChatScreen({super.key, required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Duración de mensaje efímero seleccionado (en segundos)
  int? _selectedEphemeralSeconds;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showVerifyContactDialog(BuildContext context, Contact contact, ChasquiService service) {
    final fingerprint = contact.publicKeyHex;
    final last8 = fingerprint.substring(fingerprint.length - 8);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WanadiBrand.surfaceDark,
        title: Row(
          children: [
            const Icon(Icons.verified_user_outlined, color: WanadiBrand.mintTech),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "Verificar: ${contact.alias.isNotEmpty ? contact.alias : contact.name}",
                style: const TextStyle(color: WanadiBrand.pureWhite, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Compare la huella digital completa o los últimos 8 caracteres con el contacto por otro canal seguro:",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text(
              "ÚLTIMOS 8 CARACTERES:",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: WanadiBrand.navyDeep,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                last8,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WanadiBrand.mintTech,
                  fontFamily: 'monospace',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "HUELLA COMPLETA:",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              "ed25519:$fingerprint",
              style: const TextStyle(
                color: Colors.white30,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          if (contact.isVerified)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () {
                service.toggleContactVerification(contact.publicKeyHex, false);
                Navigator.pop(context);
              },
              child: const Text("Quitar Verificación"),
            )
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: WanadiBrand.mintTech, foregroundColor: WanadiBrand.navyDeep),
              onPressed: () {
                service.toggleContactVerification(contact.publicKeyHex, true);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Contacto verificado (Candado Verde activo).")),
                );
              },
              child: const Text("Confirmado"),
            ),
        ],
      ),
    );
  }

  void _showAttachmentMenu(BuildContext context, ChasquiService service) {
    showModalBottomSheet(
      context: context,
      backgroundColor: WanadiBrand.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Enviar Archivo (Límite: 10 MB)",
                style: TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAttachmentOption(
                    icon: Icons.image,
                    label: "Imagen Real",
                    color: WanadiBrand.info,
                    onTap: () {
                      Navigator.pop(context);
                      _sendRealAttachment(service, "mision_cobertura.png", 4096); // 4 KB de bytes
                    },
                  ),
                  _buildAttachmentOption(
                    icon: Icons.insert_drive_file,
                    label: "Documento Real",
                    color: WanadiBrand.mintTech,
                    onTap: () {
                      Navigator.pop(context);
                      _sendRealAttachment(service, "informe_secreto.pdf", 8192); // 8 KB de bytes
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Generar bytes simulados reales y enviarlos fragmentados (chunking)
  void _sendRealAttachment(ChasquiService service, String filename, int byteSize) {
    final bytes = List<int>.generate(byteSize, (i) => i & 0xFF);
    service.sendAttachment(widget.contact.publicKeyHex, filename, bytes);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Cargando y fragmentando '$filename' en la red Chasqui..."),
        backgroundColor: WanadiBrand.mintTech,
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }

  void _showMessageOptions(BuildContext context, ChatMessage msg, ChasquiService service) {
    final age = DateTime.now().difference(msg.timestamp);
    final canDeleteForEveryone = msg.isSentByMe && age.inMinutes <= 10;

    showModalBottomSheet(
      context: context,
      backgroundColor: WanadiBrand.surfaceDark,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.white70),
              title: const Text("Copiar texto", style: TextStyle(color: WanadiBrand.pureWhite)),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: msg.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Copiado al portapapeles.")),
                );
              },
            ),
            if (canDeleteForEveryone)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                title: const Text("Eliminar para todos", style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text("Se borrará en ambos dispositivos", style: TextStyle(color: Colors.white30, fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  service.deleteMessage(widget.contact.publicKeyHex, msg.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Mensaje eliminado para todos.")),
                  );
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text("Eliminar localmente", style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  service.deleteMessage(widget.contact.publicKeyHex, msg.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Mensaje eliminado de este dispositivo.")),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, ChasquiService service) {
    // Calcular si ya expiró el mensaje efímero
    int remainingSeconds = 0;
    if (msg.expirationTime != null) {
      remainingSeconds = msg.expirationTime!.difference(DateTime.now()).inSeconds;
      if (remainingSeconds < 0) remainingSeconds = 0;
    }

    final isMe = msg.isSentByMe;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? WanadiBrand.mintTech.withOpacity(0.15) : WanadiBrand.surfaceDark,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
          border: Border.all(
            color: isMe ? WanadiBrand.mintTech.withOpacity(0.3) : WanadiBrand.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.isAttachment) ...[
              // Card de adjunto real
              Row(
                children: [
                  Icon(
                    msg.attachmentName!.endsWith('.png') || msg.attachmentName!.endsWith('.jpg')
                        ? Icons.image
                        : Icons.insert_drive_file,
                    color: WanadiBrand.mintTech,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.attachmentName ?? "Archivo",
                          style: const TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "${((msg.attachmentSize ?? 0) / 1024).toStringAsFixed(1)} KB",
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (msg.attachmentProgress != null && msg.attachmentProgress! < 1.0) ...[
                // Barra de progreso de subida/descarga
                LinearProgressIndicator(
                  value: msg.attachmentProgress,
                  backgroundColor: Colors.white10,
                  color: WanadiBrand.mintTech,
                ),
                const SizedBox(height: 4),
                Text(
                  "Procesando fragmentos: ${(msg.attachmentProgress! * 100).toStringAsFixed(0)}%",
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ] else ...[
                // Botón de descargar o abrir si ya se descargó localmente
                if (msg.attachmentLocalPath == null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WanadiBrand.navyDeep,
                      foregroundColor: WanadiBrand.mintTech,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    onPressed: () => service.downloadAttachment(widget.contact.publicKeyHex, msg.id),
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text("Descargar", style: TextStyle(fontSize: 12)),
                  )
                else
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: WanadiBrand.mintTech, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "Descargado localmente",
                          style: const TextStyle(color: WanadiBrand.mintTech, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: 6),
            ] else ...[
              Text(
                msg.text,
                style: const TextStyle(color: WanadiBrand.pureWhite, fontSize: 15),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (msg.ephemeralSeconds != null) ...[
                  const Icon(Icons.timer_outlined, size: 12, color: Colors.amberAccent),
                  const SizedBox(width: 4),
                  Text(
                    "${remainingSeconds}s",
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(
                  Icons.verified,
                  size: 12,
                  color: isMe ? WanadiBrand.mintTech.withOpacity(0.6) : WanadiBrand.mintTech,
                ),
                const SizedBox(width: 4),
                Text(
                  isMe ? "Cifrado" : "Verificado",
                  style: TextStyle(
                    color: isMe ? WanadiBrand.mintTech.withOpacity(0.6) : WanadiBrand.mintTech,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                
                // Indicador de estado del mensaje
                if (isMe) ...[
                  if (msg.status == "sending")
                    const Icon(Icons.access_time, size: 12, color: Colors.white24)
                  else if (msg.status == "failed")
                    const Icon(Icons.error_outline, size: 12, color: Colors.redAccent)
                  else
                    const Icon(Icons.done_all, size: 12, color: WanadiBrand.mintTech),
                  const SizedBox(width: 8),
                ],
                
                Text(
                  "${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}",
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<ChasquiService>(context);
    
    // Obtener información fresca del contacto en el directorio
    final currentContact = service.contacts.firstWhere(
      (element) => element.publicKeyHex == widget.contact.publicKeyHex,
      orElse: () => widget.contact,
    );

    final messages = service.conversations[widget.contact.publicKeyHex] ?? [];

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      backgroundColor: WanadiBrand.navyDeep,
      appBar: AppBar(
        backgroundColor: WanadiBrand.surfaceDark,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: GestureDetector(
          onTap: () => _showVerifyContactDialog(context, currentContact, service),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: currentContact.isOnline ? WanadiBrand.safe.withOpacity(0.1) : Colors.white12,
                radius: 18,
                child: Text(
                  currentContact.alias.isNotEmpty ? currentContact.alias[0].toUpperCase() : currentContact.name[0].toUpperCase(),
                  style: TextStyle(
                    color: currentContact.isOnline ? WanadiBrand.safe : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          currentContact.alias.isNotEmpty ? currentContact.alias : currentContact.name,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (currentContact.isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.lock, color: WanadiBrand.mintTech, size: 16),
                        ],
                      ],
                    ),
                    Text(
                      currentContact.isOnline ? "Online (Presencia Detectada)" : "Offline (Modo Simulado)",
                      style: TextStyle(
                        color: currentContact.isOnline ? WanadiBrand.safe : Colors.grey,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
          actions: [
//           IconButton(
//             tooltip: "Llamada de voz cifrada",
//             icon: const Icon(Icons.call, color: WanadiBrand.mintTech, size: 22),
//             onPressed: () {
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(
//                   builder: (_) => CallScreen(contact: currentContact, isVideo: false),
//                 ),
//               );
//             },
//           ),
//           IconButton(
//             tooltip: "Videollamada cifrada",
//             icon: const Icon(Icons.videocam, color: WanadiBrand.info, size: 22),
//             onPressed: () {
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(
//                   builder: (_) => CallScreen(contact: currentContact, isVideo: true),
//                 ),
//               );
//           ),
          IconButton(
            tooltip: "Verificar Contacto",
            icon: Icon(
              currentContact.isVerified ? Icons.verified : Icons.verified_outlined,
              color: currentContact.isVerified ? WanadiBrand.mintTech : Colors.white70,
            ),
            onPressed: () => _showVerifyContactDialog(context, currentContact, service),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de Estado de Red / Offline Sync Queue
          if (service.isForceOffline || !service.isNodeOnline)
            Container(
              width: double.infinity,
              color: Colors.orangeAccent.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, color: Colors.orangeAccent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    "Modo Offline activo. Mensajes en cola: ${service.offlineQueue.length}",
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: WanadiBrand.surfaceDark.withOpacity(0.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    currentContact.isVerified ? Icons.shield : Icons.shield_outlined,
                    color: currentContact.isVerified ? WanadiBrand.mintTech : WanadiBrand.warning,
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currentContact.isVerified 
                        ? "Canal de alta confianza verificado digitalmente." 
                        : "Contacto sin verificar. Pulse para comparar huellas.",
                    style: TextStyle(
                      color: currentContact.isVerified ? WanadiBrand.mintTech : WanadiBrand.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          // Message list
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_open, size: 48, color: Colors.white10),
                        const SizedBox(height: 16),
                        const Text(
                          "Comience su conversación cifrada.",
                          style: TextStyle(color: Colors.white30, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(messages[index], service);
                    },
                  ),
          ),

          // Message input
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: WanadiBrand.surfaceDark,
              child: Row(
                children: [
                  // Attachment button (+)
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white70),
                    onPressed: () => _showAttachmentMenu(context, service),
                  ),

                  // Timer/Ephemeral Button
                  PopupMenuButton<int>(
                    icon: Icon(
                      Icons.timer_outlined,
                      color: _selectedEphemeralSeconds != null ? Colors.amberAccent : Colors.white70,
                    ),
                    tooltip: "Mensaje efímero",
                    onSelected: (val) {
                      setState(() {
                        _selectedEphemeralSeconds = val == 0 ? null : val;
                      });
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 0, child: Text("Desactivado")),
                      const PopupMenuItem(value: 30, child: Text("30 segundos")),
                      const PopupMenuItem(value: 60, child: Text("1 minuto")),
                      const PopupMenuItem(value: 300, child: Text("5 minutos")),
                      const PopupMenuItem(value: 3600, child: Text("1 hora")),
                    ],
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: WanadiBrand.navyDeep,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: _selectedEphemeralSeconds != null 
                                    ? "Mensaje efímero activo..."
                                    : "Escriba un mensaje cifrado...",
                                hintStyle: const TextStyle(color: Colors.white30),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (val) {
                                if (val.trim().isNotEmpty) {
                                  service.sendMessage(
                                    widget.contact.publicKeyHex, 
                                    val.trim(),
                                    ephemeralSeconds: _selectedEphemeralSeconds,
                                  );
                                  _messageController.clear();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton.small(
                    backgroundColor: WanadiBrand.mintTech,
                    foregroundColor: WanadiBrand.navyDeep,
                    onPressed: () {
                      final text = _messageController.text.trim();
                      if (text.isNotEmpty) {
                        service.sendMessage(
                          widget.contact.publicKeyHex, 
                          text,
                          ephemeralSeconds: _selectedEphemeralSeconds,
                        );
                        _messageController.clear();
                      }
                    },
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
