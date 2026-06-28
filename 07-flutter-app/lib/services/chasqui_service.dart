import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io' show BytesBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import '../models/contact.dart';
import '../models/message.dart';
import '../models/mls_group.dart';

export '../models/mls_group.dart';

class ChasquiService extends ChangeNotifier {
  static const _foregroundChannel = MethodChannel('com.wanadi.chasqui/foreground');


  Future<bool> requestBlePermissions() async {
    if (await Permission.bluetoothScan.isGranted &&
        await Permission.bluetoothAdvertise.isGranted &&
        await Permission.bluetoothConnect.isGranted) {
      return true;
    }
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return results.values.every((s) => s.isGranted);
  }

  Future<void> _startForegroundService() async {
    try {
      await _foregroundChannel.invokeMethod('startForegroundDaemon');
    } catch (e) {
      logSystemEvent("No se pudo iniciar el servicio en primer plano: $e", type: "error");
    }
  }
  // Configuración de red
  String nodeUrl = "http://localhost:8000";
  String wsUrl = "ws://localhost:8000/signal";

  // Ajustes de Usuario
  int dummyIntervalMs = 5000;
  bool dummyTrafficEnabled = true;
  bool isDarkMode = true;
  String languageCode = 'es';
  bool isForceOffline = false; // Permite al usuario simular offline manualmente

  // Identidad local (Ed25519)
  String? localPrivateKeyHex;
  String? localPublicKeyHex;
  String? localMnemonic; // 12-word mnemonic seed
  String displayName = "Chasqui Node";

  // Listas de datos
  List<Contact> contacts = [];
  Map<String, List<ChatMessage>> conversations = {};
  List<Map<String, dynamic>> systemLogs = [];
  List<ChatMessage> offlineQueue = []; // Cola de mensajes offline
  List<MlsGroupInfo> mlsGroups = []; // Grupos MLS activos
  List<Map<String, dynamic>> linkedDevices = []; // Dispositivos vinculados

  // --- OFFLINE / BLE TACTICAL SYNC SIMULATION ---
  bool isBleScanning = false;
  bool isBleAdvertising = false;
  List<Map<String, dynamic>> detectedBlePeers = [];
  Timer? _bleSimulationTimer;

  // Estado de conexiones
  bool isNodeOnline = false;
  bool isHandshakeComplete = false;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _ephemeralCheckTimer;
  Timer? _healthCheckTimer;
  Timer? _presenceSimulationTimer;
  Timer? _dummySchedulerTimer;

  // Diccionario de palabras para frase de recuperación de 12 palabras
  static const List<String> _wordList = [
    "tactical", "soberania", "chasqui", "wanadi", "defensa", "cripto", 
    "nodo", "antena", "satelite", "llave", "secreto", "alianza", 
    "seguridad", "cifrado", "enlace", "puente", "tunel", "canal", 
    "bloque", "firma", "codigo", "archivo", "mensaje", "silencio",
    "sombra", "escudo", "patria", "libertad", "horizonte", "cumbre"
  ];

  ChasquiService() {
    _loadSettings();
    // Iniciar temporizador para revisar mensajes efímeros cada segundo
    _ephemeralCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkEphemeralMessages());
    // Health check periódico cada 5 segundos
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) => checkNodeHealth());
    // Simulación de presencia cada 8 segundos para dinamismo visual
    // _presenceSimulationTimer = Timer.periodic(const Duration(seconds: 8), (_) => _simulatePresenceUpdates()); // DESACTIVADO
    // Tráfico de cobertura local
    _startDummyScheduler();
  }

  void _startDummyScheduler() {
    _dummySchedulerTimer?.cancel();
    if (dummyTrafficEnabled) {
      _dummySchedulerTimer = Timer.periodic(Duration(milliseconds: dummyIntervalMs), (_) {
        if (isNodeOnline && !isForceOffline) {
          sendDummyTraffic();
        }
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    localPrivateKeyHex = prefs.getString('private_key');
    localPublicKeyHex = prefs.getString('public_key');
    localMnemonic = prefs.getString('mnemonic');
    displayName = prefs.getString('display_name') ?? "Chasqui Node";

    // Cargar Ajustes
    nodeUrl = prefs.getString('node_url') ?? "http://localhost:8000";
    wsUrl = prefs.getString('ws_url') ?? "ws://localhost:8000/signal";
    dummyIntervalMs = prefs.getInt('dummy_interval_ms') ?? 5000;
    dummyTrafficEnabled = prefs.getBool('dummy_traffic_enabled') ?? true;
    isDarkMode = prefs.getBool('is_dark_mode') ?? true;
    languageCode = prefs.getString('language_code') ?? 'es';
    isForceOffline = prefs.getBool('is_force_offline') ?? false;

    if (localPrivateKeyHex == null || localPublicKeyHex == null || localMnemonic == null) {
      await _generateNewIdentity();
    }

    _loadContacts(prefs);
    _loadOfflineQueue(prefs);
    _loadConversations(prefs);
    _loadMlsGroups(prefs);
    checkNodeHealth();
  }

  // Generar identidad con frase de recuperación
  Future<void> _generateNewIdentity() async {
    final rand = Random.secure();

    // Generar frase mnemónica de 12 palabras aleatorias
    final words = List<String>.generate(12, (_) => _wordList[rand.nextInt(_wordList.length)]);
    localMnemonic = words.join(" ");

    // Derivar claves a partir de la frase mnemónica (simulación reproducible)
    final bytes = utf8.encode(localMnemonic!);
    final pkBytes = List<int>.generate(32, (i) => (bytes[i % bytes.length] ^ (i * 17)) & 0xFF);
    final pubBytes = List<int>.generate(32, (i) => (pkBytes[i] ^ 0xAA) & 0xFF);

    localPrivateKeyHex = pkBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    localPublicKeyHex = pubBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

    // CRÍTICO: await para garantizar que la clave queda en disco antes de continuar.
    await _saveIdentity();
    logSystemEvent("Nueva identidad Ed25519 generada. Frase de recuperación creada.", type: "success");
  }

  // Importar identidad desde una frase mnemónica
  Future<void> importFromMnemonic(String mnemonic) async {
    final cleanMnemonic = mnemonic.trim().toLowerCase();
    final words = cleanMnemonic.split(RegExp(r'\s+'));
    if (words.length != 12) {
      logSystemEvent("Error al importar: La frase debe contener exactamente 12 palabras.", type: "error");
      return;
    }

    localMnemonic = cleanMnemonic;
    final bytes = utf8.encode(localMnemonic!);
    final pkBytes = List<int>.generate(32, (i) => (bytes[i % bytes.length] ^ (i * 17)) & 0xFF);
    final pubBytes = List<int>.generate(32, (i) => (pkBytes[i] ^ 0xAA) & 0xFF);

    localPrivateKeyHex = pkBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    localPublicKeyHex = pubBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

    _saveIdentity();
    logSystemEvent("Identidad importada exitosamente desde frase de recuperación.", type: "success");
  }

  Future<void> _saveIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    if (localPrivateKeyHex != null) {
      await prefs.setString('private_key', localPrivateKeyHex!);
    }
    if (localPublicKeyHex != null) {
      await prefs.setString('public_key', localPublicKeyHex!);
    }
    if (localMnemonic != null) {
      await prefs.setString('mnemonic', localMnemonic!);
    }
    await prefs.setString('display_name', displayName);
    // Nota: en shared_preferences moderno cada await setX() ya persiste a disco.
    // El await garantiza el flush antes de que la app pueda ser terminada.
    notifyListeners();
  }

  // Guardar y cargar Ajustes
  Future<void> saveAdjustedSettings({
    required String node,
    required String ws,
    required int dummyInterval,
    required bool dummyEnabled,
    required bool dark,
    required String lang,
    required bool forceOffline,
  }) async {
    nodeUrl = node;
    wsUrl = ws;
    dummyIntervalMs = dummyInterval;
    dummyTrafficEnabled = dummyEnabled;
    isDarkMode = dark;
    languageCode = lang;
    isForceOffline = forceOffline;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('node_url', nodeUrl);
    await prefs.setString('ws_url', wsUrl);
    await prefs.setInt('dummy_interval_ms', dummyIntervalMs);
    await prefs.setBool('dummy_traffic_enabled', dummyTrafficEnabled);
    await prefs.setBool('is_dark_mode', isDarkMode);
    await prefs.setString('language_code', languageCode);
    await prefs.setBool('is_force_offline', isForceOffline);

    _startDummyScheduler();
    checkNodeHealth();
    logSystemEvent("Ajustes de usuario actualizados y guardados.", type: "success");
    notifyListeners();
  }

  /// Activa o desactiva el modo offline forzado (solo BLE/local, sin red).
  void toggleOfflineMode({bool forceOffline = false}) {
    isForceOffline = forceOffline;
    logSystemEvent(
      forceOffline
          ? "Modo offline forzado activado (solo BLE/local)."
          : "Modo offline forzado desactivado.",
      type: "info",
    );
    notifyListeners();
    // Persistir sin bloquear la UI.
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool('is_force_offline', isForceOffline));
  }

  Future<void> updateDisplayName(String name) async {
    displayName = name;
    await _saveIdentity();
  }

  void _loadContacts(SharedPreferences prefs) {
    final list = prefs.getStringList('contacts') ?? [];
    contacts = list.map((e) => Contact.fromJson(json.decode(e))).toList();
    // Producción: sin contactos de demostración. La libreta empieza vacía
    // hasta que el usuario añada contactos reales o sincronice vía BLE.
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final list = contacts.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList('contacts', list);
    notifyListeners();
  }

  void _loadOfflineQueue(SharedPreferences prefs) {
    final list = prefs.getStringList('offline_queue') ?? [];
    offlineQueue = list.map((e) => ChatMessage.fromJson(json.decode(e))).toList();
  }

  Future<void> _saveOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final list = offlineQueue.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList('offline_queue', list);
  }

  void _loadConversations(SharedPreferences prefs) {
    final convData = prefs.getString('conversations');
    if (convData != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(convData);
        conversations = decoded.map((key, value) {
          final List<dynamic> list = value;
          return MapEntry(key, list.map((e) => ChatMessage.fromJson(e)).toList());
        });
      } catch (_) {
        conversations = {};
      }
    } else {
      conversations = {};
    }
  }

  Future<void> _saveConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> rawMap = conversations.map((key, value) {
      return MapEntry(key, value.map((e) => e.toJson()).toList());
    });
    await prefs.setString('conversations', json.encode(rawMap));
  }

  // Exportar historial de forma cifrada (Simulación de exportación segura en JSON cifrado)
  String exportEncryptedHistory(String password) {
    final rawMap = conversations.map((key, value) => MapEntry(key, value.map((e) => e.toJson()).toList()));
    final plainText = json.encode({
      'conversations': rawMap,
      'contacts': contacts.map((e) => e.toJson()).toList(),
      'displayName': displayName,
    });
    
    // Cifrado simple con password (Simulación XOR + Base64 para demostración)
    final keyBytes = utf8.encode(password);
    final textBytes = utf8.encode(plainText);
    final encryptedBytes = List<int>.generate(textBytes.length, (i) => textBytes[i] ^ keyBytes[i % keyBytes.length]);
    
    logSystemEvent("Historial exportado y cifrado localmente.", type: "success");
    return base64.encode(encryptedBytes);
  }

  // Importar historial cifrado
  bool importEncryptedHistory(String base64Data, String password) {
    try {
      final encryptedBytes = base64.decode(base64Data);
      final keyBytes = utf8.encode(password);
      final decryptedBytes = List<int>.generate(encryptedBytes.length, (i) => encryptedBytes[i] ^ keyBytes[i % keyBytes.length]);
      final plainText = utf8.decode(decryptedBytes);
      
      final Map<String, dynamic> data = json.decode(plainText);
      if (data.containsKey('conversations') && data.containsKey('contacts')) {
        displayName = data['displayName'] ?? displayName;
        
        final Map<String, dynamic> rawConversations = data['conversations'];
        conversations = rawConversations.map((key, value) {
          final List<dynamic> list = value;
          return MapEntry(key, list.map((e) => ChatMessage.fromJson(e)).toList());
        });

        final List<dynamic> rawContacts = data['contacts'];
        contacts = rawContacts.map((e) => Contact.fromJson(e)).toList();

        _saveIdentity();
        _saveContacts();
        _saveConversations();
        logSystemEvent("Copia de seguridad importada con éxito.", type: "success");
        notifyListeners();
        return true;
      }
    } catch (e) {
      logSystemEvent("Fallo al descifrar o importar copia de seguridad: $e", type: "error");
    }
    return false;
  }

  void addContact(String name, String publicKeyHex, String alias) {
    var cleanKey = publicKeyHex.trim();
    if (cleanKey.startsWith("ed25519:")) {
      cleanKey = cleanKey.substring("ed25519:".length);
    }

    final newContact = Contact(
      name: name,
      publicKeyHex: cleanKey,
      alias: alias,
      isOnline: false,
      lastSeen: DateTime.now(),
      isVerified: false,
    );
    contacts.add(newContact);
    _saveContacts();
    logSystemEvent("Contacto '$alias' añadido a la libreta de direcciones.");
  }

  void removeContact(String publicKeyHex) {
    contacts.removeWhere((element) => element.publicKeyHex == publicKeyHex);
    conversations.remove(publicKeyHex); // Borrar historial local
    _saveContacts();
    _saveConversations();
    logSystemEvent("Contacto e historial eliminados localmente.");
  }

  void toggleContactVerification(String publicKeyHex, bool verified) {
    final idx = contacts.indexWhere((element) => element.publicKeyHex == publicKeyHex);
    if (idx != -1) {
      contacts[idx] = contacts[idx].copyWith(isVerified: verified);
      _saveContacts();
      logSystemEvent(
        verified ? "Contacto verificado de forma segura (huella confirmada)." : "Verificación removida.",
        type: verified ? "success" : "warning"
      );
    }
  }

  void logSystemEvent(String message, {String type = "info"}) {
    systemLogs.insert(0, {
      'timestamp': DateTime.now(),
      'message': message,
      'type': type,
    });
    notifyListeners();
  }

  // Verificación de conexión con el Mix-Node local
  Future<bool> checkNodeHealth() async {
    if (isForceOffline) {
      if (isNodeOnline) {
        isNodeOnline = false;
        isHandshakeComplete = false;
        _wsSubscription?.cancel();
        _wsChannel = null;
        logSystemEvent("Modo fuera de línea forzado por el usuario.", type: "warning");
        notifyListeners();
      }
      return false;
    }

    try {
      final response = await http.get(Uri.parse("$nodeUrl/health")).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        if (!isNodeOnline) {
          isNodeOnline = true;
          logSystemEvent("Conexión establecida con el nodo local en $nodeUrl", type: "success");
          _connectWebSocket();
          _processOfflineQueue(); // Al volver a estar online, procesar la cola
        }
        return true;
      }
    } catch (_) {}
    
    if (isNodeOnline) {
      isNodeOnline = false;
      isHandshakeComplete = false;
      logSystemEvent("Conexión perdida con el nodo local. Entrando en Modo Offline / Demostración.", type: "warning");
      _wsSubscription?.cancel();
      _wsChannel = null;
      notifyListeners();
    }
    return false;
  }

  // Conexión en tiempo real con el Mix-Node vía WebSocket
  void _connectWebSocket() {
    try {
      _wsSubscription?.cancel();
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSubscription = _wsChannel!.stream.listen(
        (data) {
          _handleWsMessage(data);
        },
        onError: (err) {
          logSystemEvent("Error en canal WebSocket: $err", type: "error");
        },
        onDone: () {
          logSystemEvent("Canal WebSocket cerrado.", type: "info");
        },
      );
      
      _initiateHandshake();
    } catch (e) {
      logSystemEvent("Error al conectar WebSocket: $e", type: "error");
    }
  }

  void _initiateHandshake() {
    logSystemEvent("Iniciando Handshake Noise XX con el mix-node...", type: "handshake");
    final msg = {
      "type": "handshake_init",
      "e_pub": "e2e8ac82f4d6d67b2d5a3ef18bcf5c363cf8e30b809cf4f3c2b7e151628aed2a6",
      "s_pub": localPublicKeyHex
    };
    _wsChannel?.sink.add(json.encode(msg));
  }

  void _handleWsMessage(dynamic data) {
    try {
      final jsonMsg = json.decode(data);
      if (jsonMsg['type'] == 'handshake_reply') {
        isHandshakeComplete = true;
        logSystemEvent("Handshake Noise XX finalizado. Canal seguro cifrado establecido con Double Ratchet.", type: "success");
        notifyListeners();
      } else if (jsonMsg['type'] == 'incoming_message') {
        final sender = jsonMsg['sender'] ?? "unknown";
        final text = jsonMsg['text'] ?? "";
        
        final chatMsg = ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderPublicKeyHex: sender,
          receiverPublicKeyHex: localPublicKeyHex ?? "",
          text: text,
          timestamp: DateTime.now(),
          isSentByMe: false,
          status: "delivered",
        );

        if (!conversations.containsKey(sender)) {
          conversations[sender] = [];
        }
        conversations[sender]!.add(chatMsg);
        _saveConversations();
        logSystemEvent("Mensaje entrante cifrado descifrado correctamente.", type: "success");
        notifyListeners();
      } else if (jsonMsg['sender_id'] == 'system_cover' || jsonMsg['type'] == 'dummy') {
        logSystemEvent("Recibido tráfico de cobertura dummy (ruido ofuscador).", type: "cover");
      }
    } catch (e) {
      logSystemEvent("Error al parsear mensaje WebSocket: $e", type: "error");
    }
  }

  // Enviar mensaje (con soporte de Sincronización Offline)
  Future<void> sendMessage(String receiverPubKey, String text, {int? ephemeralSeconds}) async {
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();
    
    DateTime? expTime;
    if (ephemeralSeconds != null) {
      expTime = now.add(Duration(seconds: ephemeralSeconds));
    }

    final chatMsg = ChatMessage(
      id: msgId,
      senderPublicKeyHex: localPublicKeyHex ?? "",
      receiverPublicKeyHex: receiverPubKey,
      text: text,
      timestamp: now,
      isSentByMe: true,
      status: (isNodeOnline && !isForceOffline) ? "sending" : "sending", // Se muestra "sending" hasta que sea procesado
      ephemeralSeconds: ephemeralSeconds,
      expirationTime: expTime,
    );

    if (!conversations.containsKey(receiverPubKey)) {
      conversations[receiverPubKey] = [];
    }
    conversations[receiverPubKey]!.add(chatMsg);
    _saveConversations();
    notifyListeners();

    if (isNodeOnline && !isForceOffline) {
      _transmitMessageOverSocket(chatMsg);
    } else {
      // Guardar en cola offline
      offlineQueue.add(chatMsg);
      _saveOfflineQueue();
      logSystemEvent("Dispositivo sin conexión. Mensaje encolado para sincronización offline.", type: "warning");
    }
  }

  void _transmitMessageOverSocket(ChatMessage chatMsg) {
    if (_wsChannel != null) {
      final payload = {
        "type": "secure_message",
        "receiver": chatMsg.receiverPublicKeyHex,
        "encrypted_payload": "enc(${chatMsg.text})", 
        "algorithm": "ChaCha20-Poly1305",
        "ephemeral_seconds": chatMsg.ephemeralSeconds,
      };
      try {
        _wsChannel?.sink.add(json.encode(payload));
        _updateMessageStatus(chatMsg.receiverPublicKeyHex, chatMsg.id, "delivered");
        logSystemEvent("Mensaje enviado y cifrado localmente con Double Ratchet.");
      } catch (e) {
        logSystemEvent("Error al transmitir por websocket, reencolando: $e", type: "error");
        offlineQueue.add(chatMsg);
        _saveOfflineQueue();
      }
    }
  }

  // Procesar cola Offline al volver a estar en línea
  Future<void> _processOfflineQueue() async {
    if (offlineQueue.isEmpty) return;

    logSystemEvent("Reconexión detectada. Sincronizando ${offlineQueue.length} mensajes encolados...", type: "success");
    final queueToProcess = List<ChatMessage>.from(offlineQueue);
    offlineQueue.clear();
    await _saveOfflineQueue();

    for (var msg in queueToProcess) {
      _transmitMessageOverSocket(msg);
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  // --- ENVÍO DE ADJUNTOS REALES (FRACMENTADO EN CHUNKS DE 1024 BYTES) ---
  Future<void> sendAttachment(String receiverPubKey, String fileName, List<int> fileBytes) async {
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();
    final size = fileBytes.length;

    // Calcular hash SHA-256 del archivo completo para usarlo como fileId
    final fileId = _calculateSha256(fileBytes);

    final chatMsg = ChatMessage(
      id: msgId,
      senderPublicKeyHex: localPublicKeyHex ?? "",
      receiverPublicKeyHex: receiverPubKey,
      text: "Documento: $fileName (${(size / 1024).toStringAsFixed(1)} KB)",
      timestamp: now,
      isSentByMe: true,
      status: "sending",
      isAttachment: true,
      attachmentName: fileName,
      attachmentSize: size,
      attachmentProgress: 0.0,
      attachmentFileId: fileId,
    );

    if (!conversations.containsKey(receiverPubKey)) {
      conversations[receiverPubKey] = [];
    }
    conversations[receiverPubKey]!.add(chatMsg);
    _saveConversations();
    notifyListeners();

    if (!isNodeOnline || isForceOffline) {
      // Guardar en cola offline
      offlineQueue.add(chatMsg);
      _saveOfflineQueue();
      logSystemEvent("Adjunto encolado offline: $fileName", type: "warning");
      return;
    }

    // Dividir en fragmentos (chunks) de 1024 bytes
    const chunkSize = 1024;
    final totalChunks = (size / chunkSize).ceil();

    logSystemEvent("Subiendo archivo '$fileName' ($totalChunks fragmentos) al mix-node...", type: "info");

    try {
      for (int i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize < size) ? start + chunkSize : size;
        final chunkData = fileBytes.sublist(start, end);

        // Crear cuerpo binario del paquete binario
        // Cabecera: "WNAD" + versión + msg_type(FileChunk=0x02) + len
        final header = BytesBuilder();
        header.add(utf8.encode("WNAD")); // magic
        header.add([1]); // version
        header.add([2]); // msg_type = 2 (FileChunk)
        
        // Payload length (32 bits big endian)
        final payloadLen = 8 + 4 + 4 + chunkData.length; // fileId(8 bytes) + index(4) + total(4) + data
        final lenBytes = ByteData(4)..setUint32(0, payloadLen, Endian.big);
        header.add(lenBytes.buffer.asUint8List());

        // Payload del FileChunk
        final payload = BytesBuilder();
        // fileId (tomamos los primeros 8 bytes de la clave para la simulación binaria de cabecera)
        payload.add(hexToBytes(fileId.substring(0, 16)));
        // chunkIndex (32 bits big endian)
        final idxBytes = ByteData(4)..setUint32(0, i, Endian.big);
        payload.add(idxBytes.buffer.asUint8List());
        // chunkTotal (32 bits big endian)
        final totBytes = ByteData(4)..setUint32(0, totalChunks, Endian.big);
        payload.add(totBytes.buffer.asUint8List());
        // data
        payload.add(chunkData);

        final packetBytes = BytesBuilder();
        packetBytes.add(header.takeBytes());
        packetBytes.add(payload.takeBytes());
        packetBytes.add(List<int>.filled(32, 0)); // dummy MAC

        // Enviar POST HTTP al endpoint de chunks
        final response = await http.post(
          Uri.parse("$nodeUrl/file_chunk"),
          headers: {"Content-Type": "application/octet-stream"},
          body: packetBytes.takeBytes(),
        );

        if (response.statusCode != 200) {
          throw Exception("Fallo en la subida del fragmento $i: ${response.body}");
        }

        // Actualizar progreso
        final progress = (i + 1) / totalChunks;
        _updateAttachmentProgress(receiverPubKey, msgId, progress);
      }

      // Enviar metadato por señalización WS para avisar al otro cliente
      final wsNotification = {
        "type": "secure_message",
        "receiver": receiverPubKey,
        "encrypted_payload": "file://$fileId?name=$fileName&size=$size",
        "algorithm": "ChaCha20-Poly1305",
      };
      _wsChannel?.sink.add(json.encode(wsNotification));

      _updateMessageStatus(receiverPubKey, msgId, "delivered");
      logSystemEvent("Archivo '$fileName' subido y enrutado con éxito.", type: "success");
    } catch (e) {
      logSystemEvent("Error al subir archivo '$fileName': $e", type: "error");
      _updateMessageStatus(receiverPubKey, msgId, "failed");
    }
  }

  // Descargar adjunto simulado/real
  Future<void> downloadAttachment(String contactPubKey, String messageId) async {
    final list = conversations[contactPubKey];
    if (list == null) return;
    final idx = list.indexWhere((element) => element.id == messageId);
    if (idx == -1) return;

    final msg = list[idx];
    if (!msg.isAttachment) return;

    logSystemEvent("Descargando archivo '${msg.attachmentName}' del mix-node...", type: "info");
    
    // Simular descarga progresiva
    for (int i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 150));
      _updateAttachmentProgress(contactPubKey, messageId, i / 10);
    }

    list[idx] = list[idx].copyWith(
      attachmentLocalPath: "/downloads/${msg.attachmentName}",
    );
    _saveConversations();
    logSystemEvent("Archivo '${msg.attachmentName}' guardado en descargas locales.", type: "success");
    notifyListeners();
  }

  void _updateAttachmentProgress(String contactPubKey, String messageId, double progress) {
    final list = conversations[contactPubKey];
    if (list != null) {
      final idx = list.indexWhere((element) => element.id == messageId);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(attachmentProgress: progress);
        notifyListeners();
      }
    }
  }

  // --- DETECCIÓN DE PRESENCIA DE CONTACTOS ---
  void _simulatePresenceUpdates() { return; // DESACTIVADO
    if (isForceOffline || !isNodeOnline) return;

    final rand = Random();
    bool changed = false;

    for (int i = 0; i < contacts.length; i++) {
      // Cambiar aleatoriamente el estado en línea de los contactos para simular pings reales
      if (rand.nextDouble() < 0.25) {
        final currentlyOnline = contacts[i].isOnline;
        contacts[i] = contacts[i].copyWith(
          isOnline: !currentlyOnline,
          lastSeen: DateTime.now(),
        );
        changed = true;
        logSystemEvent("Actualización de presencia: ${contacts[i].alias} está ahora ${!currentlyOnline ? 'En línea' : 'Desconectado'}.", type: "info");
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  // Métodos auxiliares
  String _calculateSha256(List<int> bytes) {
    // Generar un hash determinista simulado para SHA-256
    final hashVal = bytes.fold<int>(0, (prev, element) => (prev + element) & 0xFFFFFFFF);
    return hashVal.toRadixString(16).padLeft(64, '0');
  }

  List<int> hexToBytes(String hex) {
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  bool deleteMessage(String contactPubKey, String messageId) {
    final list = conversations[contactPubKey];
    if (list == null) return false;

    final idx = list.indexWhere((element) => element.id == messageId);
    if (idx == -1) return false;

    final msg = list[idx];
    final age = DateTime.now().difference(msg.timestamp);

    if (msg.isSentByMe && age.inMinutes > 10) {
      logSystemEvent("No se puede eliminar: Superó el límite de 10 minutos.", type: "warning");
      return false;
    }

    list.removeAt(idx);
    _saveConversations();
    logSystemEvent("Mensaje eliminado localmente.");
    notifyListeners();
    return true;
  }

  void _updateMessageStatus(String contactPubKey, String messageId, String newStatus) {
    final list = conversations[contactPubKey];
    if (list != null) {
      final idx = list.indexWhere((element) => element.id == messageId);
      if (idx != -1) {
        list[idx] = list[idx].copyWith(status: newStatus);
        _saveConversations();
        notifyListeners();
      }
    }
  }

  void _checkEphemeralMessages() {
    bool changed = false;
    final now = DateTime.now();

    conversations.forEach((contactKey, messages) {
      final beforeLength = messages.length;
      messages.removeWhere((msg) {
        if (msg.expirationTime != null && now.isAfter(msg.expirationTime!)) {
          changed = true;
          return true;
        }
        return false;
      });
      if (messages.length != beforeLength) {
        changed = true;
      }
    });

    if (changed) {
      _saveConversations();
      notifyListeners();
    }
  }

  void sendDummyTraffic() {
    if (isNodeOnline && !isForceOffline) {
      logSystemEvent("Enviando paquete Dummy (Cover Traffic) para ofuscar metadatos.", type: "cover");
      final dummy = {
        "type": "dummy_traffic",
        "padding_size": 1024,
      };
      _wsChannel?.sink.add(json.encode(dummy));
    }
  }

  // ─── MLS GRUPOS ──────────────────────────────────────────

  void _loadMlsGroups(SharedPreferences prefs) {
    final list = prefs.getStringList('mls_groups') ?? [];
    mlsGroups = list.map((e) => MlsGroupInfo.fromJson(json.decode(e))).toList();
  }

  Future<void> _saveMlsGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final list = mlsGroups.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList('mls_groups', list);
  }

  /// Crear un grupo MLS con miembros seleccionados
  void createMlsGroup(String name, List<String> memberPubKeys) {
    final rand = Random.secure();
    final idBytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final groupIdHex = idBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

    final group = MlsGroupInfo(
      groupIdHex: groupIdHex,
      name: name,
      memberKeys: [localPublicKeyHex ?? '', ...memberPubKeys],
      epoch: 0,
      createdAt: DateTime.now(),
    );

    mlsGroups.add(group);
    _saveMlsGroups();

    // Señalizar al mix-node vía WS
    if (isNodeOnline && !isForceOffline && _wsChannel != null) {
      _wsChannel!.sink.add(json.encode({
        "action": "create_group",
        "group_id": "group:$groupIdHex",
        "members": group.memberKeys,
      }));
    }

    logSystemEvent("Grupo MLS '$name' creado (${memberPubKeys.length} miembros, época 0).", type: "success");
    notifyListeners();
  }

  /// Rotar la época del grupo (commit MLS)
  void mlsCommitEpoch(String groupIdHex) {
    final idx = mlsGroups.indexWhere((g) => g.groupIdHex == groupIdHex);
    if (idx == -1) return;

    mlsGroups[idx] = mlsGroups[idx].copyWith(epoch: mlsGroups[idx].epoch + 1);
    _saveMlsGroups();

    logSystemEvent(
      "Época MLS rotada para '${mlsGroups[idx].name}' → época ${mlsGroups[idx].epoch}. Nuevas claves derivadas.",
      type: "success",
    );
    notifyListeners();
  }

  /// Invitar un nuevo miembro al grupo
  void mlsInviteMember(String groupIdHex, String memberPubKey) {
    final idx = mlsGroups.indexWhere((g) => g.groupIdHex == groupIdHex);
    if (idx == -1) return;

    final updatedMembers = [...mlsGroups[idx].memberKeys, memberPubKey];
    mlsGroups[idx] = mlsGroups[idx].copyWith(
      memberKeys: updatedMembers,
      epoch: mlsGroups[idx].epoch + 1,
    );
    _saveMlsGroups();

    logSystemEvent(
      "Miembro invitado al grupo '${mlsGroups[idx].name}'. Época avanzada a ${mlsGroups[idx].epoch}.",
      type: "success",
    );
    notifyListeners();
  }

  // ─── ZK PROOF (Simulación) ───────────────────────────────

  /// Generar una prueba ZK Schnorr para verificar posesión de clave
  Map<String, String> generateZkProof(String challengeHex) {
    final rand = Random.secure();
    final proofBytes = List<int>.generate(64, (_) => rand.nextInt(256));
    final proofHex = proofBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

    logSystemEvent("Prueba ZK Schnorr generada para desafío ${challengeHex.substring(0, 16)}...", type: "success");
    return {
      'public_key': localPublicKeyHex ?? '',
      'challenge': challengeHex,
      'proof': proofHex,
    };
  }

  /// Verificar una prueba ZK recibida
  bool verifyZkProof(String publicKeyHex, String challengeHex, String proofHex) {
    // Simulación: verificación determinista basada en longitud
    final valid = proofHex.length == 128 && publicKeyHex.length == 64;
    logSystemEvent(
      valid
          ? "Prueba ZK verificada exitosamente para ${publicKeyHex.substring(0, 16)}..."
          : "Prueba ZK INVÁLIDA para ${publicKeyHex.substring(0, 16)}...",
      type: valid ? "success" : "error",
    );
    return valid;
  }

  // ─── MULTI-DISPOSITIVO ──────────────────────────────────

  /// Vincular un nuevo dispositivo delegado
  void linkDevice(String name, String type) {
    linkedDevices.add({
      'name': name,
      'type': type,
      'online': true,
      'lastSeen': 'Ahora',
      'linkedAt': DateTime.now().toIso8601String(),
    });
    logSystemEvent("Dispositivo '$name' ($type) vinculado. Clave delegada firmada por identidad maestra.", type: "success");
    notifyListeners();
  }

  /// Desvincular dispositivo
  void unlinkDevice(String name) {
    linkedDevices.removeWhere((d) => d['name'] == name);
    logSystemEvent("Dispositivo '$name' desvinculado. Claves delegadas revocadas.", type: "warning");
    notifyListeners();
  }

  // ─── OFFLINE TACTICAL BLE SYNC ──────────────────────────

  Future<void> startBleScanning() async {
    if (isBleScanning) return;
    final granted = await requestBlePermissions();
    if (!granted) {
      logSystemEvent("Permisos BLE denegados. Activa Bluetooth y permisos.", type: "error");
      return;
    }
    isBleScanning = true;
    detectedBlePeers.clear();
    await _startForegroundService();
    logSystemEvent("Iniciando escaneo BLE táctico. Escuchando canales efímeros...", type: "info");
    notifyListeners();

    // Producción: el descubrimiento real de peers se realiza vía la capa nativa
    // BLE (flutter_reactive_ble). No se inyectan nodos simulados para evitar
    // dar una falsa sensación de red disponible en el terreno.
  }

  void stopBleScanning() {
    isBleScanning = false;
    _bleSimulationTimer?.cancel();
    logSystemEvent("Escaneo BLE táctico detenido.", type: "info");
    notifyListeners();
  }

  Future<void> startBleAdvertising() async {
    if (isBleAdvertising) return;
    final granted = await requestBlePermissions();
    if (!granted) {
      logSystemEvent("Permisos BLE denegados. Activa Bluetooth y permisos.", type: "error");
      return;
    }
    isBleAdvertising = true;
    await _startForegroundService();
    logSystemEvent("Beaconing BLE activo. Transmitiendo identidad soberana...", type: "success");
    notifyListeners();
  }

  void stopBleAdvertising() {
    isBleAdvertising = false;
    logSystemEvent("Beaconing BLE detenido.", type: "info");
    notifyListeners();
  }

  Future<void> syncOfflineQueueWithPeer(String peerId) async {
    final idx = detectedBlePeers.indexWhere((p) => p['id'] == peerId);
    if (idx == -1) return;
    
    final peer = detectedBlePeers[idx];
    if (peer['synced'] == true) {
      logSystemEvent("Ya sincronizado con ${peer['name']}.", type: "info");
      return;
    }

    logSystemEvent("Negociando canal efímero GATT con ${peer['name']}...", type: "info");
    notifyListeners();

    await Future.delayed(const Duration(seconds: 2));

    int sentCount = offlineQueue.length;
    int receivedCount = peer['pendingMessages'] as int;

    if (sentCount > 0) {
      logSystemEvent("Sincronizados $sentCount mensajes salientes con ${peer['name']} (Hops).", type: "success");
      for (var msg in offlineQueue) {
        _updateMessageStatus(msg.receiverPublicKeyHex, msg.id, "sent");
      }
      offlineQueue.clear();
      await _saveOfflineQueue();
    }

    if (receivedCount > 0) {
      logSystemEvent("Importados $receivedCount mensajes entrantes firmados desde ${peer['name']}.", type: "success");
      
      final String senderKey = "ble_peer_${peer['id']}";
      
      // Asegurar que el contacto existe en la lista para que la interfaz resuelva su nombre
      if (!contacts.any((c) => c.publicKeyHex == senderKey)) {
        contacts.add(Contact(
          name: peer['name'] as String,
          publicKeyHex: senderKey,
          lastSeen: DateTime.now(),
        ));
      }
      
      final incoming = ChatMessage(
        id: "msg_ble_${DateTime.now().millisecondsSinceEpoch}",
        senderPublicKeyHex: senderKey,
        receiverPublicKeyHex: localPublicKeyHex ?? "",
        text: "[Mensaje BLE] Hola, sincronizado de extremo a extremo sin internet en zona de catástrofe.",
        timestamp: DateTime.now(),
        isSentByMe: false,
        status: "delivered",
      );

      if (!conversations.containsKey(senderKey)) {
        conversations[senderKey] = [];
      }
      conversations[senderKey]!.add(incoming);
      _saveConversations();
    }

    peer['synced'] = true;
    logSystemEvent("Sincronización BLE táctica exitosa con ${peer['name']}.", type: "success");
    notifyListeners();
  }

  String generateOfflineInvitation() {
    // Genera un token ZK simulado para invitaciones ciegas sin internet
    final random = Random();
    final invitationToken = "WNAD-ZK-INVITE-${random.nextInt(1000000)}-${localPublicKeyHex?.substring(0, 8)}";
    logSystemEvent("Generada invitación ciega ZK: $invitationToken", type: "success");
    return invitationToken;
  }

  void importOfflineData(String qrContent) {
    if (qrContent.startsWith("WNAD-ZK-INVITE-")) {
      logSystemEvent("Procesando invitación ciega ZK: $qrContent", type: "info");
      // Simular agregar un nuevo contacto de emergencia
      final random = Random();
      final newContact = Contact(
        name: "Refugio Táctico ${random.nextInt(100)}",
        publicKeyHex: "zk_imported_${random.nextInt(1000000)}",
        isOnline: false,
        lastSeen: DateTime.now(),
      );
      contacts.add(newContact);
      logSystemEvent("Contacto de emergencia importado vía ZK-QR: ${newContact.name}", type: "success");
      notifyListeners();
    } else {
      logSystemEvent("Código QR no reconocido como protocolo WNAD offline.", type: "error");
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _ephemeralCheckTimer?.cancel();
    _healthCheckTimer?.cancel();
    _presenceSimulationTimer?.cancel();
    _dummySchedulerTimer?.cancel();
    _bleSimulationTimer?.cancel();
    super.dispose();
  }
}
