import 'package:flutter/foundation.dart';

/// 充电桩实体模型，存储单个车库充电桩的编号、别名、原始链接及覆盖模板。
class ChargingStation {
  const ChargingStation({
    required this.id,
    required this.alias,
    required this.serialNumber,
    required this.rawUrl,
    this.address,
    this.portCount,
    this.gunNums,
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
  final String? address;
  final int? portCount;
  final List<String>? gunNums;
  final String? customDeepLinkTemplate;
  final int lastUsedPort;
  final DateTime lastUsedDate;

  /// 获取第 [port] (1-based) 个插座的真实编号（优先使用云端下发的 gun_num，其次回退起始偏置）。
  String socketLabel(int port, int defaultBase) {
    final idx = port - 1;
    final list = gunNums;
    if (list != null && idx >= 0 && idx < list.length) {
      return list[idx];
    }
    return (idx + defaultBase).clamp(0, 99).toString();
  }

  ChargingStation copyWith({
    String? id,
    String? alias,
    String? serialNumber,
    String? rawUrl,
    String? address,
    bool clearAddress = false,
    int? portCount,
    List<String>? gunNums,
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
      address: clearAddress ? null : (address ?? this.address),
      portCount: portCount ?? this.portCount,
      gunNums: gunNums ?? this.gunNums,
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
      'address': address,
      'portCount': portCount,
      'gunNums': gunNums,
      'customDeepLinkTemplate': customDeepLinkTemplate,
      'lastUsedPort': lastUsedPort,
      'lastUsedDate': lastUsedDate.toIso8601String(),
    };
  }

  factory ChargingStation.fromJson(Map<String, dynamic> json) {
    final rawPort = (json['lastUsedPort'] as num?)?.toInt() ?? 1;
    final rawPortCount = (json['portCount'] as num?)?.toInt();
    final rawGunNums = json['gunNums'];
    final parsedGunNums = rawGunNums is List
        ? rawGunNums
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : null;
    final rawTemplate = json['customDeepLinkTemplate'] as String?;
    final rawAddress = json['address'] as String?;
    return ChargingStation(
      id: json['id'] as String? ?? '',
      alias: json['alias'] as String? ?? '未命名充电桩',
      serialNumber: (json['serialNumber'] as String? ?? '').toUpperCase(),
      rawUrl: json['rawUrl'] as String? ?? '',
      address: (rawAddress != null && rawAddress.trim().isNotEmpty)
          ? rawAddress.trim()
          : null,
      portCount: (rawPortCount != null && rawPortCount >= 1 && rawPortCount <= 12)
          ? rawPortCount
          : null,
      gunNums: (parsedGunNums != null && parsedGunNums.isNotEmpty)
          ? parsedGunNums
          : null,
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
        other.address == address &&
        other.portCount == portCount &&
        listEquals(other.gunNums, gunNums) &&
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
        address,
        portCount,
        gunNums == null ? null : Object.hashAll(gunNums!),
        customDeepLinkTemplate,
        lastUsedPort,
        lastUsedDate,
      );
}
