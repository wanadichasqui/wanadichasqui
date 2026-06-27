/// Modelo para representar un grupo MLS activo en la app.
class MlsGroupInfo {
  final String groupIdHex;
  final String name;
  final List<String> memberKeys; // Public keys hex de los miembros
  final int epoch;
  final DateTime createdAt;

  MlsGroupInfo({
    required this.groupIdHex,
    required this.name,
    required this.memberKeys,
    this.epoch = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'groupIdHex': groupIdHex,
    'name': name,
    'memberKeys': memberKeys,
    'epoch': epoch,
    'createdAt': createdAt.toIso8601String(),
  };

  factory MlsGroupInfo.fromJson(Map<String, dynamic> json) => MlsGroupInfo(
    groupIdHex: json['groupIdHex'] as String,
    name: json['name'] as String,
    memberKeys: List<String>.from(json['memberKeys'] as List),
    epoch: json['epoch'] as int? ?? 0,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  MlsGroupInfo copyWith({
    String? groupIdHex,
    String? name,
    List<String>? memberKeys,
    int? epoch,
    DateTime? createdAt,
  }) {
    return MlsGroupInfo(
      groupIdHex: groupIdHex ?? this.groupIdHex,
      name: name ?? this.name,
      memberKeys: memberKeys ?? this.memberKeys,
      epoch: epoch ?? this.epoch,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
