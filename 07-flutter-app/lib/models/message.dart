class ChatMessage {
  final String id;
  final String senderPublicKeyHex;
  final String receiverPublicKeyHex;
  final String text;
  final DateTime timestamp;
  final bool isSentByMe;
  final bool isEncrypted;
  final String? algorithm; // e.g., "Noise-XX + Double Ratchet (ChaCha20-Poly1305)"
  final bool isDecryptedSuccessfully;
  final String status; // "sending", "delivered"
  final int? ephemeralSeconds; // null if not ephemeral
  final DateTime? expirationTime; // Calculated when message is created/delivered

  // Attachment fields
  final bool isAttachment;
  final String? attachmentName;
  final int? attachmentSize;
  final double? attachmentProgress; // 0.0 to 1.0
  final String? attachmentLocalPath;
  final String? attachmentFileId;

  ChatMessage({
    required this.id,
    required this.senderPublicKeyHex,
    required this.receiverPublicKeyHex,
    required this.text,
    required this.timestamp,
    required this.isSentByMe,
    this.isEncrypted = true,
    this.algorithm = "ChaCha20-Poly1305 (Double Ratchet)",
    this.isDecryptedSuccessfully = true,
    this.status = "delivered",
    this.ephemeralSeconds,
    this.expirationTime,
    this.isAttachment = false,
    this.attachmentName,
    this.attachmentSize,
    this.attachmentProgress,
    this.attachmentLocalPath,
    this.attachmentFileId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderPublicKeyHex': senderPublicKeyHex,
        'receiverPublicKeyHex': receiverPublicKeyHex,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'isSentByMe': isSentByMe,
        'isEncrypted': isEncrypted,
        'algorithm': algorithm,
        'isDecryptedSuccessfully': isDecryptedSuccessfully,
        'status': status,
        'ephemeralSeconds': ephemeralSeconds,
        'expirationTime': expirationTime?.toIso8601String(),
        'isAttachment': isAttachment,
        'attachmentName': attachmentName,
        'attachmentSize': attachmentSize,
        'attachmentProgress': attachmentProgress,
        'attachmentLocalPath': attachmentLocalPath,
        'attachmentFileId': attachmentFileId,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        senderPublicKeyHex: json['senderPublicKeyHex'] as String,
        receiverPublicKeyHex: json['receiverPublicKeyHex'] as String,
        text: json['text'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        isSentByMe: json['isSentByMe'] as bool,
        isEncrypted: json['isEncrypted'] as bool? ?? true,
        algorithm: json['algorithm'] as String?,
        isDecryptedSuccessfully: json['isDecryptedSuccessfully'] as bool? ?? true,
        status: json['status'] as String? ?? "delivered",
        ephemeralSeconds: json['ephemeralSeconds'] as int?,
        expirationTime: json['expirationTime'] != null
            ? DateTime.parse(json['expirationTime'] as String)
            : null,
        isAttachment: json['isAttachment'] as bool? ?? false,
        attachmentName: json['attachmentName'] as String?,
        attachmentSize: json['attachmentSize'] as int?,
        attachmentProgress: (json['attachmentProgress'] as num?)?.toDouble(),
        attachmentLocalPath: json['attachmentLocalPath'] as String?,
        attachmentFileId: json['attachmentFileId'] as String?,
      );

  ChatMessage copyWith({
    String? id,
    String? senderPublicKeyHex,
    String? receiverPublicKeyHex,
    String? text,
    DateTime? timestamp,
    bool? isSentByMe,
    bool? isEncrypted,
    String? algorithm,
    bool? isDecryptedSuccessfully,
    String? status,
    int? ephemeralSeconds,
    DateTime? expirationTime,
    bool? isAttachment,
    String? attachmentName,
    int? attachmentSize,
    double? attachmentProgress,
    String? attachmentLocalPath,
    String? attachmentFileId,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderPublicKeyHex: senderPublicKeyHex ?? this.senderPublicKeyHex,
      receiverPublicKeyHex: receiverPublicKeyHex ?? this.receiverPublicKeyHex,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isSentByMe: isSentByMe ?? this.isSentByMe,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      algorithm: algorithm ?? this.algorithm,
      isDecryptedSuccessfully: isDecryptedSuccessfully ?? this.isDecryptedSuccessfully,
      status: status ?? this.status,
      ephemeralSeconds: ephemeralSeconds ?? this.ephemeralSeconds,
      expirationTime: expirationTime ?? this.expirationTime,
      isAttachment: isAttachment ?? this.isAttachment,
      attachmentName: attachmentName ?? this.attachmentName,
      attachmentSize: attachmentSize ?? this.attachmentSize,
      attachmentProgress: attachmentProgress ?? this.attachmentProgress,
      attachmentLocalPath: attachmentLocalPath ?? this.attachmentLocalPath,
      attachmentFileId: attachmentFileId ?? this.attachmentFileId,
    );
  }
}
