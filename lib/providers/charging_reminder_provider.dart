import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/background_queue_worker.dart';
import '../services/notification_service.dart';
import '../services/station_lookup_service.dart';
import '../services/storage_service.dart';
import 'app_providers.dart';

/// 定时取车/拔枪提醒与插口结束监测状态管理：
/// - 支持按小时倒计时兜底（前台 Timer + 后台 WorkManager）
/// - 支持同步监测目标插口状态：一旦从「充电中」转为「空闲中」，立刻推送结束通知
class ChargingReminderNotifier extends StateNotifier<ChargingReminderRecord?> {
  ChargingReminderNotifier(
    this._storage,
    this._notifications, {
    this.onCompleted,
  }) : super(_storage.loadChargingReminder()) {
    _syncTimer();
  }

  final StorageService _storage;
  final NotificationService _notifications;
  final void Function(String stationId, String portLabel)? onCompleted;
  Timer? _timer;
  bool _sawBusyOnWatchedSlot = false;

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    final current = state;
    if (current == null) return;

    final remaining = current.remindAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      unawaited(_fireNow(current));
      return;
    }

    _timer = Timer(remaining, () => unawaited(_fireNow(current)));
  }

  Future<void> _fireNow(ChargingReminderRecord record) async {
    await _notifications.showChargingReminderNotification(
      stationName: record.stationName,
      portLabel: record.portLabel,
    );
    if (record.watchStationId != null) {
      onCompleted?.call(record.watchStationId!, record.portLabel);
    }
    await clearReminder();
  }

  Future<void> setReminder({
    required String stationName,
    required String portLabel,
    required Duration delay,
    String? watchStationId,
    int? watchSlot,
  }) async {
    _sawBusyOnWatchedSlot = false;
    final record = ChargingReminderRecord(
      stationName: stationName,
      portLabel: portLabel,
      remindAt: DateTime.now().add(delay),
      watchStationId: watchStationId,
      watchSlot: watchSlot,
    );
    state = record;
    await _storage.saveChargingReminder(record);
    await BackgroundQueueWorker.scheduleChargingReminder(delay);
    _syncTimer();
  }

  /// 由实时轮询回调：若监测中的插口先处于充电中，之后变成空闲中，立即触发充电结束提醒。
  Future<void> onLiveStationUpdated(
    String stationId,
    StationLiveInfo info,
  ) async {
    if (info.isStatusStale) return;
    final current = state;
    if (current == null ||
        current.watchStationId != stationId ||
        current.watchSlot == null) {
      return;
    }

    final status = info.gunStatuses[current.watchSlot!];
    if (status == GunWorkStatus.busy) {
      _sawBusyOnWatchedSlot = true;
    } else if (_sawBusyOnWatchedSlot && status == GunWorkStatus.idle) {
      _sawBusyOnWatchedSlot = false;
      await _fireNow(current);
    }
  }

  Future<void> clearReminder() async {
    _timer?.cancel();
    _timer = null;
    _sawBusyOnWatchedSlot = false;
    state = null;
    await _storage.clearChargingReminder();
    await BackgroundQueueWorker.cancelChargingReminder();
    await _notifications.cancelChargingReminderNotification();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// 刚刚充满待拔电的充电桩映射（stationId -> socketLabel），用于卡片显示「满电结束」视觉效果。
final recentlyCompletedStationsProvider =
    StateProvider<Map<String, String>>((ref) => const {});

final chargingReminderProvider =
    StateNotifierProvider<ChargingReminderNotifier, ChargingReminderRecord?>(
        (ref) {
  final storage = ref.watch(storageServiceProvider);
  final notifications = ref.watch(notificationServiceProvider);
  return ChargingReminderNotifier(
    storage,
    notifications,
    onCompleted: (stationId, portLabel) {
      final current = ref.read(recentlyCompletedStationsProvider);
      ref.read(recentlyCompletedStationsProvider.notifier).state = {
        ...current,
        stationId: portLabel,
      };
    },
  );
});
