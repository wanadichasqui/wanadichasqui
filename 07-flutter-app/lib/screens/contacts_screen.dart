import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chasqui_service.dart';
import '../models/contact.dart';
import '../main.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _pubKeyController = TextEditingController();
  final TextEditingController _aliasController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _pubKeyController.dispose();
    _aliasController.dispose();
    super.dispose();
  }

  void _showAddContactDialog(BuildContext context, ChasquiService service) {
    _nameController.clear();
    _pubKeyController.clear();
    _aliasController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WanadiBrand.surfaceDark,
        title: const Text(
          "Añadir Contacto",
          style: TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                style: const TextStyle(color: WanadiBrand.pureWhite),
                decoration: const InputDecoration(
                  labelText: "Nombre completo",
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _aliasController,
                style: const TextStyle(color: WanadiBrand.pureWhite),
                decoration: const InputDecoration(
                  labelText: "Alias",
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pubKeyController,
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: "Clave Pública (Hex o ed25519:...)",
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                ),
              ),
            ],
          ),
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
              final name = _nameController.text.trim();
              final alias = _aliasController.text.trim();
              final pubKey = _pubKeyController.text.trim();

              // La clave limpia puede o no tener el prefijo
              var cleanKey = pubKey;
              if (cleanKey.startsWith("ed25519:")) {
                cleanKey = cleanKey.substring("ed25519:".length);
              }

              if (name.isNotEmpty && cleanKey.length == 64) {
                service.addContact(name, pubKey, alias.isEmpty ? name : alias);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Contacto guardado.")),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Ingrese un nombre y una clave pública válida de 64 caracteres.")),
                );
              }
            },
            child: const Text("Agregar"),
          ),
        ],
      ),
    );
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
              "Compare la huella digital completa o los últimos 8 caracteres con el contacto por otro canal de comunicación seguro:",
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "DIRECTORIO",
                        style: TextStyle(
                          color: WanadiBrand.mintTech,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            "Mis Contactos",
                            style: TextStyle(
                              color: WanadiBrand.pureWhite,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "${service.contacts.length}",
                              style: const TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  FloatingActionButton.small(
                    backgroundColor: WanadiBrand.mintTech,
                    foregroundColor: WanadiBrand.navyDeep,
                    onPressed: () => _showAddContactDialog(context, service),
                    child: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Contacts list
              Expanded(
                child: service.contacts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.contacts_outlined,
                              size: 64,
                              color: Colors.grey.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "No tienes contactos guardados.",
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: service.contacts.length,
                        itemBuilder: (context, index) {
                          final contact = service.contacts[index];
                          final initials = (contact.alias.isNotEmpty
                                  ? contact.alias
                                  : contact.name)
                              .substring(0, 1)
                              .toUpperCase();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: WanadiBrand.surfaceDark,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: WanadiBrand.divider),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: contact.isOnline
                                        ? WanadiBrand.safe.withOpacity(0.1)
                                        : WanadiBrand.mintTech.withOpacity(0.1),
                                    child: Text(
                                      initials,
                                      style: TextStyle(
                                        color: contact.isOnline
                                            ? WanadiBrand.safe
                                            : WanadiBrand.mintTech,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: contact.isOnline ? WanadiBrand.safe : Colors.grey,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: WanadiBrand.surfaceDark, width: 2),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    contact.alias.isNotEmpty ? contact.alias : contact.name,
                                    style: const TextStyle(
                                      color: WanadiBrand.pureWhite,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (contact.isVerified) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.lock, color: WanadiBrand.mintTech, size: 16),
                                  ],
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  "ed25519:${contact.publicKeyHex.substring(0, 8)}...${contact.publicKeyHex.substring(contact.publicKeyHex.length - 8)}",
                                  style: const TextStyle(
                                    color: Colors.white30,
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.verified_user_outlined, color: WanadiBrand.mintTech, size: 20),
                                    tooltip: "Verificar identidad",
                                    onPressed: () => _showVerifyContactDialog(context, contact, service),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chat_bubble_outline, color: WanadiBrand.info, size: 20),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ChatScreen(contact: contact),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    onPressed: () {
                                      service.removeContact(contact.publicKeyHex);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text("Contacto e historial eliminados.")),
                                      );
                                    },
                                  ),
                                ],
                              ),
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
