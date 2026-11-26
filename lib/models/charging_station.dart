/// 充电桩实体模型，存储单个车库充电桩的编号、别名、原始链接及覆盖模板。
class ChargingStation {
  const ChargingStation({
    required this.id,
    required this.alias,
    required this.serialNumber,
    required this.rawUrl,
    this.customDeepLinkTemplate,
    int lastUsedPort = 1,
    required this.lastUsedDate,
  }) : lastUsedPort = lastUsedPort < 1
            ? 1
            : (lastUsedPort > 12 ? 12 : lastUsedPort);

  final String id;
  final String alias;
  final String serialNumber;
  final String rawUrl;
  final String? customDeepLinkTemplate;
  final int lastUsedPort;
  final DateTime lastUsedDate;

  ChargingStation copyWith({
    String? id,
    String? alias,
    String? serialNumber,
    String? rawUrl,
    String? customDeepLinkTemplate,
    bool clearCustomDeepLinkTemplate = false,
    int? lastUsedPort,
    DateTime? lastUsedDate,
  }) {
    final nextPort = lastUsedPort ?? this.lastUsedPort;
    return ChargingStation(
      id: id ?? this.id,
      alias: alias ?? this.alias,
      serialNumber: serialNumber ?? this.serialNumber,
      rawUrl: rawUrl ?? this.rawUrl,
      customDeepLinkTemplate: clearCustomDeepLinkTemplate
          ? null
          : (customDeepLinkTemplate ?? this.customDeepLinkTemplate),
      lastUsedPort: nextPort.clamp(1, 12),
      lastUsedDate: lastUsedDate ?? this.lastUsedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'alias': alias,
      'serialNumber': serialNumber,
      'rawUrl': rawUrl,
      'customDeepLinkTemplate': customDeepLinkTemplate,
      'lastUsedPort': lastUsedPort,
      'lastUsedDate': lastUsedDate.toIso8601String(),
    };
  }

  factory ChargingStation.fromJson(Map<String, dynamic> json) {
    final rawPort = (json['lastUsedPort'] as num?)?.toInt() ?? 1;
    final rawTemplate = json['customDeepLinkTemplate'] as String?;
    return ChargingStation(
      id: json['id'] as String? ?? '',
      alias: json['alias'] as String? ?? '未命名充电桩',
      serialNumber: (json['serialNumber'] as String? ?? '').toUpperCase(),
      rawUrl: json['rawUrl'] as String? ?? '',
      customDeepLinkTemplate:
          (rawTemplate != null && rawTemplate.trim().isNotEmpty)
              ? rawTemplate.trim()
              : null,
      lastUsedPort: rawPort.clamp(1, 12),
      lastUsedDate: DateTime.tryParse(json['lastUsedDate'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChargingStation &&
        other.id == id &&
        other.alias == alias &&
        other.serialNumber == serialNumber &&
        other.rawUrl == rawUrl &&
        other.customDeepLinkTemplate == customDeepLinkTemplate &&
        other.lastUsedPort == lastUsedPort &&
        other.lastUsedDate == lastUsedDate;
  }

  @override
  int get hashCode => Object.hash(
        id,
        alias,
        serialNumber,
        rawUrl,
        customDeepLinkTemplate,
        lastUsedPort,
        lastUsedDate,
      );
}
