import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/charging_station.dart';
import '../services/storage_service.dart';
import 'app_providers.dart';

/// 本地充电足迹管理：每次成功拉起支付宝去充电时自动记一笔（最多保留 20 条）。
class ChargingHistoryNotifier
    extends StateNotifier<List<ChargingHistoryRecord>> {
  ChargingHistoryNotifier(this._storage)
      : super(_storage.loadChargingHistory());

  final StorageService _storage;

  Future<void> recordLaunch({
    required ChargingStation station,
    required String socketLabel,
  }) async {
    final entry = ChargingHistoryRecord(
      stationId: station.id,
      stationAlias: station.alias,
      serialNumber: station.serialNumber,
      socketLabel: socketLabel,
      triggeredAt: DateTime.now(),
    );
    final next = [entry, ...state].take(20).toList();
    state = next;
    await _storage.saveChargingHistory(next);
  }

  Future<void> clearAll() async {
    state = [];
    await _storage.clearChargingHistory();
  }
}

final chargingHistoryProvider = StateNotifierProvider<ChargingHistoryNotifier,
    List<ChargingHistoryRecord>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return ChargingHistoryNotifier(storage);
});
