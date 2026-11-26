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
          rawUrl: 'https://charge.example.com/start?sn=W52001715',
          lastUsedPort: 1,
          lastUsedDate: now,
        ),
        ChargingStation(
          id: 'seed-w52001414',
          alias: 'B2-B区 2号桩',
          serialNumber: 'W52001414',
          rawUrl: 'https://charge.example.com/start?sn=W52001414',
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
}
