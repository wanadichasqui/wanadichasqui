import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chasqui_service.dart';
import '../main.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _groupNameController = TextEditingController();

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  void _showCreateGroupDialog(ChasquiService service) {
    _groupNameController.clear();
    final selectedContacts = <String>{};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: WanadiBrand.surfaceDark,
          title: const Text("Crear Grupo MLS", style: TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _groupNameController,
                  style: const TextStyle(color: WanadiBrand.pureWhite),
                  decoration: InputDecoration(
                    labelText: "Nombre del grupo",
                    labelStyle: const TextStyle(color: Colors.grey),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: WanadiBrand.mintTech.withOpacity(0.3))),
                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: WanadiBrand.mintTech)),
                  ),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("SELECCIONAR MIEMBROS", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: service.contacts.length,
                    itemBuilder: (_, i) {
                      final c = service.contacts[i];
                      final selected = selectedContacts.contains(c.publicKeyHex);
                      return CheckboxListTile(
                        dense: true,
                        activeColor: WanadiBrand.mintTech,
                        title: Text(c.alias.isNotEmpty ? c.alias : c.name, style: const TextStyle(color: WanadiBrand.pureWhite, fontSize: 14)),
                        subtitle: Text(c.publicKeyHex.substring(0, 16) + "...", style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace')),
                        value: selected,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              selectedContacts.add(c.publicKeyHex);
                            } else {
                              selectedContacts.remove(c.publicKeyHex);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: WanadiBrand.mintTech, foregroundColor: WanadiBrand.navyDeep),
              onPressed: () {
                final name = _groupNameController.text.trim();
                if (name.isEmpty || selectedContacts.isEmpty) return;
                service.createMlsGroup(name, selectedContacts.toList());
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Grupo '$name' creado con ${selectedContacts.length} miembros."), backgroundColor: WanadiBrand.safe),
                );
              },
              child: const Text("Crear Grupo"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WanadiBrand.navyDeep,
      floatingActionButton: FloatingActionButton(
        backgroundColor: WanadiBrand.mintTech,
        foregroundColor: WanadiBrand.navyDeep,
        onPressed: () => _showCreateGroupDialog(Provider.of<ChasquiService>(context, listen: false)),
        child: const Icon(Icons.group_add),
      ),
      body: SafeArea(
        child: Consumer<ChasquiService>(
          builder: (context, service, _) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("GRUPOS MLS", style: TextStyle(color: WanadiBrand.mintTech, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  const Text("Mensajería Grupal Cifrada", style: TextStyle(color: WanadiBrand.pureWhite, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    "Grupos con Messaging Layer Security (RFC 9420). Cada época genera nuevas claves — si un miembro sale, el historial anterior queda sellado.",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  if (service.mlsGroups.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: WanadiBrand.surfaceDark,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: WanadiBrand.divider),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.groups_outlined, color: WanadiBrand.mintTech.withOpacity(0.4), size: 64),
                          const SizedBox(height: 16),
                          const Text("Sin grupos activos", style: TextStyle(color: Colors.grey, fontSize: 15)),
                          const SizedBox(height: 8),
                          const Text("Pulsa + para crear un grupo cifrado MLS.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  else
                    ...service.mlsGroups.map((group) => _buildGroupCard(group, service)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGroupCard(MlsGroupInfo group, ChasquiService service) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WanadiBrand.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WanadiBrand.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: WanadiBrand.mintTech.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups, color: WanadiBrand.mintTech, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: const TextStyle(color: WanadiBrand.pureWhite, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text("${group.memberKeys.length} miembros · Época ${group.epoch}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: WanadiBrand.safe.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: WanadiBrand.safe.withOpacity(0.3)),
                ),
                child: const Text("MLS", style: TextStyle(color: WanadiBrand.safe, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.vpn_key, color: Colors.grey, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "ID: ${group.groupIdHex.substring(0, 24)}...",
                  style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: WanadiBrand.mintTech.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => service.mlsCommitEpoch(group.groupIdHex),
                  icon: const Icon(Icons.refresh, size: 16, color: WanadiBrand.mintTech),
                  label: const Text("Rotar Época", style: TextStyle(color: WanadiBrand.mintTech, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: WanadiBrand.info.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {},
                  icon: const Icon(Icons.chat_bubble_outline, size: 16, color: WanadiBrand.info),
                  label: const Text("Chat", style: TextStyle(color: WanadiBrand.info, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
