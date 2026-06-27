class Contact {
  final String name;
  final String publicKeyHex;
  final String alias;
  final bool isOnline;
  final DateTime lastSeen;
  final bool isVerified;

  Contact({
    required this.name,
    required this.publicKeyHex,
    this.alias = '',
    this.isOnline = false,
    required this.lastSeen,
    this.isVerified = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'publicKeyHex': publicKeyHex,
        'alias': alias,
        'isOnline': isOnline,
        'lastSeen': lastSeen.toIso8601String(),
        'isVerified': isVerified,
      };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        name: json['name'] as String,
        publicKeyHex: json['publicKeyHex'] as String,
        alias: json['alias'] as String? ?? '',
        isOnline: json['isOnline'] as bool? ?? false,
        lastSeen: DateTime.parse(json['lastSeen'] as String),
        isVerified: json['isVerified'] as bool? ?? false,
      );

  Contact copyWith({
    String? name,
    String? publicKeyHex,
    String? alias,
    bool? isOnline,
    DateTime? lastSeen,
    bool? isVerified,
  }) {
    return Contact(
      name: name ?? this.name,
      publicKeyHex: publicKeyHex ?? this.publicKeyHex,
      alias: alias ?? this.alias,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}
