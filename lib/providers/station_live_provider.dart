import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/charging_station.dart';
import '../services/station_lookup_service.dart';
import 'app_providers.dart';
import 'charging_reminder_provider.dart';

class StationLiveState {
  const StationLiveState({
    this.byStationId = const {},
    this.refreshingIds = const {},
    this.isRefreshingAll = false,
  });

  final Map<String, StationLiveInfo> byStationId;
  final Set<String> refreshingIds;
  final bool isRefreshingAll;

  StationLiveState copyWith({
    Map<String, StationLiveInfo>? byStationId,
    Set<String>? refreshingIds,
    bool? isRefreshingAll,
  }) {
    return StationLiveState(
      byStationId: byStationId ?? this.byStationId,
      refreshingIds: refreshingIds ?? this.refreshingIds,
      isRefreshingAll: isRefreshingAll ?? this.isRefreshingAll,
    );
  }
}

/// 充电桩实时状态控制器：
/// - 仅在有网且处于前台时每 15 秒静默轮询各桩插口空闲/占用状态与电价套餐；
/// - 离线或切入后台自动暂停轮询，省电零消耗，同时保留最后一次拉取到的状态供参考。
class StationLiveNotifier extends StateNotifier<StationLiveState> {
  StationLiveNotifier({
    required List<ChargingStation> Function() readStations,
    required bool Function() readIsOnline,
    required bool Function() readIsForeground,
    Future<StationLiveInfo?> Function(
      String serialNumber, {
      double? cachedElectricityFees,
      List<String>? cachedPackages,
    })? fetchLive,
    Future<void> Function(String stationId, StationLiveInfo info)?
        onMetadataSynced,
    bool enableAutoPolling = true,
  })  : _readStations = readStations,
        _readIsOnline = readIsOnline,
        _readIsForeground = readIsForeground,
        _fetchLive = fetchLive ?? _defaultFetch,
        _onMetadataSynced = onMetadataSynced,
        super(const StationLiveState()) {
    if (enableAutoPolling) {
      syncPolling();
      if (_readIsOnline() && _readIsForeground()) {
        unawaited(refreshAll());
      }
    }
  }

  static Future<StationLiveInfo?> _defaultFetch(
    String serialNumber, {
    double? cachedElectricityFees,
    List<String>? cachedPackages,
  }) {
    return StationLookupService.fetchLiveStatus(
      serialNumber,
      includePackages: true,
      cachedElectricityFees: cachedElectricityFees,
      cachedPackages: cachedPackages,
    );
  }

  final List<ChargingStation> Function() _readStations;
  final bool Function() _readIsOnline;
  final bool Function() _readIsForeground;
  final Future<StationLiveInfo?> Function(
    String serialNumber, {
    double? cachedElectricityFees,
    List<String>? cachedPackages,
  }) _fetchLive;
  final Future<void> Function(String stationId, StationLiveInfo info)?
      _onMetadataSynced;

  Timer? _pollTimer;

  void syncPolling() {
    final shouldPoll = _readIsOnline() && _readIsForeground();
    if (!shouldPoll) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_readIsOnline() && _readIsForeground()) {
        unawaited(refreshAll());
      } else {
        syncPolling();
      }
    });
  }

  Future<void> refreshAll() async {
    if (!mounted || state.isRefreshingAll) return;
    final stations = _readStations();
    if (stations.isEmpty) return;

    state = state.copyWith(isRefreshingAll: true);
    try {
      await Future.wait(stations.map((s) => refreshStation(s.id)));
    } finally {
      if (mounted) {
        state = state.copyWith(isRefreshingAll: false);
      }
    }
  }

  Future<void> refreshStation(String stationId) async {
    if (!mounted) return;
    final station =
        _readStations().where((s) => s.id == stationId).firstOrNull;
    if (station == null) return;

    final existing = state.byStationId[stationId];
    state = state.copyWith(
      refreshingIds: {...state.refreshingIds, stationId},
    );

    try {
      final info = await _fetchLive(
        station.serialNumber,
        cachedElectricityFees: existing?.electricityFees,
        cachedPackages: existing?.packages,
      );
      if (!mounted || info == null) return;
      state = state.copyWith(
        byStationId: {...state.byStationId, stationId: info},
      );
      if (_onMetadataSynced != null) {
        await _onMetadataSynced(stationId, info);
      }
    } finally {
      if (mounted) {
        final nextIds = {...state.refreshingIds}..remove(stationId);
        state = state.copyWith(refreshingIds: nextIds);
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final stationLiveProvider =
    StateNotifierProvider<StationLiveNotifier, StationLiveState>((ref) {
  final notifier = StationLiveNotifier(
    readStations: () => ref.read(stationsProvider),
    readIsOnline: () => ref.read(launchQueueProvider).isOnline,
    readIsForeground: () => ref.read(launchQueueProvider).isAppInForeground,
    onMetadataSynced: (stationId, info) async {
      await ref.read(stationsProvider.notifier).syncLiveMetadata(
            stationId,
            portCount: info.totalGunCount,
            gunNums: info.gunNums,
            locationInfo: info.locationInfo,
          );
      await ref
          .read(chargingReminderProvider.notifier)
          .onLiveStationUpdated(stationId, info);
    },
  );

  ref.listen<bool>(
    launchQueueProvider.select((s) => s.isOnline),
    (prev, next) {
      notifier.syncPolling();
      if (next && prev != true) {
        unawaited(notifier.refreshAll());
      }
    },
  );

  ref.listen<bool>(
    launchQueueProvider.select((s) => s.isAppInForeground),
    (prev, next) {
      notifier.syncPolling();
      if (next && prev == false && ref.read(launchQueueProvider).isOnline) {
        unawaited(notifier.refreshAll());
      }
    },
  );

  ref.listen<List<ChargingStation>>(stationsProvider, (prev, next) {
    if ((prev?.length ?? 0) < next.length &&
        ref.read(launchQueueProvider).isOnline) {
      unawaited(notifier.refreshStation(next.first.id));
    }
  });

  return notifier;
});
