import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/charging_station.dart';

/// 离线排队持久化记录
class PendingQueueRecord {
  const PendingQueueRecord({
    required this.stationId,
    required this.port,
    required this.queuedAt,
  });

  final String stationId;
  final int port;
  final DateTime queuedAt;
}

/// 基于 SharedPreferences 的本地持久化服务（零原生编译依赖）。
class StorageService {
  StorageService(this._prefs);

  final SharedPreferences _prefs;

  static const String _stationsKey = 'charge_quick_stations_v1';
  static const String _settingsKey = 'charge_quick_settings_v1';
  static const String _hasSeededKey = 'charge_quick_has_seeded_v1';
  static const String _pendingStationIdKey = 'charge_quick_pending_station_id';
  static const String _pendingPortKey = 'charge_quick_pending_port';
  static const String _pendingAtKey = 'charge_quick_pending_at';

  /// 首次启动预置示例充电桩数据，方便立即测试。
  Future<List<ChargingStation>> loadStationsOrSeed() async {
    final hasSeeded = _prefs.getBool(_hasSeededKey) ?? false;
    final rawJson = _prefs.getString(_stationsKey);

    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        final list = decoded
            .whereType<Map<String, dynamic>>()
            .map(ChargingStation.fromJson)
            .toList();
        if (list.isNotEmpty || hasSeeded) {
          return list;
        }
      } catch (_) {
        // 解析异常时回退到种子数据
      }
    }

    if (!hasSeeded) {
      final now = DateTime.now();
      final seedStations = [
        ChargingStation(
          id: 'seed-w52001715',
          alias: 'B2-A区 1号桩',
          serialNumber: 'W52001715',
          rawUrl: 'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52001715',
          lastUsedPort: 1,
          lastUsedDate: now,
        ),
        ChargingStation(
          id: 'seed-w52001414',
          alias: 'B2-B区 2号桩',
          serialNumber: 'W52001414',
          rawUrl: 'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52001414',
          lastUsedPort: 2,
          lastUsedDate: now.subtract(const Duration(hours: 6)),
        ),
      ];
      await saveStations(seedStations);
      await _prefs.setBool(_hasSeededKey, true);
      return seedStations;
    }

    return [];
  }

  Future<void> saveStations(List<ChargingStation> stations) async {
    final encoded = jsonEncode(stations.map((s) => s.toJson()).toList());
    await _prefs.setString(_stationsKey, encoded);
  }

  AppSettings loadSettings() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) {
      return const AppSettings();
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AppSettings.fromJson(map);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  PendingQueueRecord? loadPendingQueue() {
    final stationId = _prefs.getString(_pendingStationIdKey);
    final port = _prefs.getInt(_pendingPortKey);
    if (stationId == null || stationId.isEmpty || port == null) {
      return null;
    }
    final queuedAt =
        DateTime.tryParse(_prefs.getString(_pendingAtKey) ?? '') ??
            DateTime.now();
    return PendingQueueRecord(
      stationId: stationId,
      port: port.clamp(1, 12),
      queuedAt: queuedAt,
    );
  }

  Future<void> savePendingQueue({
    required String stationId,
    required int port,
  }) async {
    await _prefs.setString(_pendingStationIdKey, stationId);
    await _prefs.setInt(_pendingPortKey, port.clamp(1, 12));
    await _prefs.setString(_pendingAtKey, DateTime.now().toIso8601String());
  }

  Future<void> clearPendingQueue() async {
    await _prefs.remove(_pendingStationIdKey);
    await _prefs.remove(_pendingPortKey);
    await _prefs.remove(_pendingAtKey);
  }

  static const String _reminderStationKey = 'charging_reminder_station';
  static const String _reminderPortLabelKey = 'charging_reminder_port_label';
  static const String _reminderAtKey = 'charging_reminder_at';
  static const String _reminderWatchStationIdKey =
      'charging_reminder_watch_station_id';
  static const String _reminderWatchSlotKey = 'charging_reminder_watch_slot';

  ChargingReminderRecord? loadChargingReminder() {
    final stationName = _prefs.getString(_reminderStationKey);
    final rawAt = _prefs.getString(_reminderAtKey);
    if (stationName == null || stationName.isEmpty || rawAt == null) {
      return null;
    }
    final remindAt = DateTime.tryParse(rawAt);
    if (remindAt == null) return null;
    return ChargingReminderRecord(
      stationName: stationName,
      portLabel: _prefs.getString(_reminderPortLabelKey) ?? '',
      remindAt: remindAt,
      watchStationId: _prefs.getString(_reminderWatchStationIdKey),
      watchSlot: _prefs.getInt(_reminderWatchSlotKey),
    );
  }

  Future<void> saveChargingReminder(ChargingReminderRecord record) async {
    await _prefs.setString(_reminderStationKey, record.stationName);
    await _prefs.setString(_reminderPortLabelKey, record.portLabel);
    await _prefs.setString(_reminderAtKey, record.remindAt.toIso8601String());
    if (record.watchStationId != null && record.watchSlot != null) {
      await _prefs.setString(
        _reminderWatchStationIdKey,
        record.watchStationId!,
      );
      await _prefs.setInt(_reminderWatchSlotKey, record.watchSlot!);
    } else {
      await _prefs.remove(_reminderWatchStationIdKey);
      await _prefs.remove(_reminderWatchSlotKey);
    }
  }

  Future<void> clearChargingReminder() async {
    await _prefs.remove(_reminderStationKey);
    await _prefs.remove(_reminderPortLabelKey);
    await _prefs.remove(_reminderAtKey);
    await _prefs.remove(_reminderWatchStationIdKey);
    await _prefs.remove(_reminderWatchSlotKey);
  }

  static const String _historyKey = 'charging_history_records';

  List<ChargingHistoryRecord> loadChargingHistory() {
    final raw = _prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(ChargingHistoryRecord.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveChargingHistory(List<ChargingHistoryRecord> records) async {
    final trimmed = records.take(20).toList();
    await _prefs.setString(
      _historyKey,
      jsonEncode(trimmed.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> clearChargingHistory() async {
    await _prefs.remove(_historyKey);
  }
}

class ChargingHistoryRecord {
  const ChargingHistoryRecord({
    required this.stationId,
    required this.stationAlias,
    required this.serialNumber,
    required this.socketLabel,
    required this.triggeredAt,
    this.amountYuan,
  });

  final String stationId;
  final String stationAlias;
  final String serialNumber;
  final String socketLabel;
  final DateTime triggeredAt;
  final double? amountYuan;

  ChargingHistoryRecord copyWith({
    double? amountYuan,
    bool clearAmount = false,
  }) {
    return ChargingHistoryRecord(
      stationId: stationId,
      stationAlias: stationAlias,
      serialNumber: serialNumber,
      socketLabel: socketLabel,
      triggeredAt: triggeredAt,
      amountYuan: clearAmount ? null : (amountYuan ?? this.amountYuan),
    );
  }

  Map<String, dynamic> toJson() => {
        'stationId': stationId,
        'stationAlias': stationAlias,
        'serialNumber': serialNumber,
        'socketLabel': socketLabel,
        'triggeredAt': triggeredAt.toIso8601String(),
        if (amountYuan != null) 'amountYuan': amountYuan,
      };

  factory ChargingHistoryRecord.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amountYuan'];
    return ChargingHistoryRecord(
      stationId: json['stationId'] as String? ?? '',
      stationAlias: json['stationAlias'] as String? ?? '',
      serialNumber: json['serialNumber'] as String? ?? '',
      socketLabel: json['socketLabel'] as String? ?? '',
      triggeredAt: DateTime.tryParse(json['triggeredAt'] as String? ?? '') ??
          DateTime.now(),
      amountYuan: rawAmount is num ? rawAmount.toDouble() : null,
    );
  }
}

class ChargingReminderRecord {
  const ChargingReminderRecord({
    required this.stationName,
    required this.portLabel,
    required this.remindAt,
    this.watchStationId,
    this.watchSlot,
  });

  final String stationName;
  final String portLabel;
  final DateTime remindAt;
  final String? watchStationId;
  final int? watchSlot;
}
