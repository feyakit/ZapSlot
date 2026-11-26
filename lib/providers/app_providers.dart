import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/charging_station.dart';
import '../services/launch_queue_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';

/// 在 main.dart 中通过 ProviderScope overrides 注入已初始化实例
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

final storageServiceProvider = Provider<StorageService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return StorageService(prefs);
});

/// 充电桩列表状态管理
class StationsNotifier extends StateNotifier<List<ChargingStation>> {
  StationsNotifier(this._storage, List<ChargingStation> initialStations)
      : super(initialStations);

  final StorageService _storage;
  static const Uuid _uuid = Uuid();

  Future<ChargingStation> upsertStation({
    String? id,
    required String alias,
    required String serialNumber,
    required String rawUrl,
    String? customDeepLinkTemplate,
    bool preserveCustomTemplateIfNull = false,
    int lastUsedPort = 1,
  }) async {
    final normalizedSn = serialNumber.trim().toUpperCase();
    final trimmedAlias = alias.trim().isEmpty ? normalizedSn : alias.trim();
    final trimmedRaw = rawUrl.trim();
    final trimmedCustom = customDeepLinkTemplate?.trim();
    final now = DateTime.now();

    final existingIndex = id != null
        ? state.indexWhere((s) => s.id == id)
        : state.indexWhere((s) => s.serialNumber == normalizedSn);

    late ChargingStation saved;
    if (existingIndex >= 0) {
      final current = state[existingIndex];
      final hasProvidedCustom =
          trimmedCustom != null && trimmedCustom.isNotEmpty;
      final shouldClearCustom =
          !preserveCustomTemplateIfNull && !hasProvidedCustom;
      saved = current.copyWith(
        alias: trimmedAlias,
        serialNumber: normalizedSn,
        rawUrl: trimmedRaw.isNotEmpty ? trimmedRaw : current.rawUrl,
        customDeepLinkTemplate: hasProvidedCustom ? trimmedCustom : null,
        clearCustomDeepLinkTemplate: shouldClearCustom,
        lastUsedPort: lastUsedPort,
        lastUsedDate: now,
      );
      final updated = [...state];
      updated[existingIndex] = saved;
      // 最近使用的桩置顶，方便单手快速点按
      updated.removeAt(existingIndex);
      updated.insert(0, saved);
      state = updated;
    } else {
      saved = ChargingStation(
        id: id ?? _uuid.v4(),
        alias: trimmedAlias,
        serialNumber: normalizedSn,
        rawUrl: trimmedRaw,
        customDeepLinkTemplate:
            (trimmedCustom != null && trimmedCustom.isNotEmpty)
                ? trimmedCustom
                : null,
        lastUsedPort: lastUsedPort,
        lastUsedDate: now,
      );
      state = [saved, ...state];
    }

    await _storage.saveStations(state);
    return saved;
  }

  Future<void> updateLastUsedPort(String stationId, int port) async {
    final index = state.indexWhere((s) => s.id == stationId);
    if (index < 0) return;
    final updatedList = [...state];
    updatedList[index] = updatedList[index].copyWith(
      lastUsedPort: port,
      lastUsedDate: DateTime.now(),
    );
    state = updatedList;
    await _storage.saveStations(state);
  }

  /// 扫码 / OCR 静默入库：
  /// 已收录的桩只更新原始二维码链接（保留别名、上次插座号与自定义直达模板），
  /// 未收录的桩按桩号尾号自动命名新建并置顶。返回最终保存的实体。
  Future<ChargingStation> collectScannedStation({
    required String serialNumber,
    required String rawUrl,
    String? alias,
  }) async {
    final normalizedSn = serialNumber.trim().toUpperCase();
    final index = state.indexWhere((s) => s.serialNumber == normalizedSn);

    if (index >= 0) {
      final current = state[index];
      final updated = current.copyWith(rawUrl: rawUrl.trim());
      if (updated == current) return current;
      final next = [...state]
        ..removeAt(index)
        ..insert(0, updated);
      state = next;
      await _storage.saveStations(state);
      return updated;
    }

    final tail = normalizedSn.length > 4
        ? normalizedSn.substring(normalizedSn.length - 4)
        : normalizedSn;
    return upsertStation(
      alias: (alias != null && alias.trim().isNotEmpty)
          ? alias.trim()
          : '车库桩 $tail',
      serialNumber: normalizedSn,
      rawUrl: rawUrl,
      preserveCustomTemplateIfNull: true,
    );
  }

  Future<void> deleteStation(String stationId) async {
    state = state.where((s) => s.id != stationId).toList();
    await _storage.saveStations(state);
  }
}

final initialStationsProvider = Provider<List<ChargingStation>>((ref) {
  throw UnimplementedError('initialStationsProvider must be overridden');
});

final stationsProvider =
    StateNotifierProvider<StationsNotifier, List<ChargingStation>>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final initial = ref.watch(initialStationsProvider);
  return StationsNotifier(storage, initial);
});

/// 全局规则配置状态管理
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._storage) : super(_storage.loadSettings());

  final StorageService _storage;

  Future<void> updateSettings(AppSettings next) async {
    state = next;
    await _storage.saveSettings(next);
  }

  Future<void> updateGlobalTemplate(String template) async {
    final trimmed = template.trim();
    if (trimmed.isEmpty) return;
    await updateSettings(state.copyWith(globalUrlTemplate: trimmed));
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return SettingsNotifier(storage);
});

final launchQueueProvider =
    StateNotifierProvider<LaunchQueueNotifier, LaunchQueueState>((ref) {
  final storage = ref.watch(storageServiceProvider);
  final notifications = ref.watch(notificationServiceProvider);

  final notifier = LaunchQueueNotifier(
    storage: storage,
    notifications: notifications,
    readStations: () => ref.read(stationsProvider),
    readSettings: () => ref.read(settingsProvider),
    onStationUsed: (stationId, port) =>
        ref.read(stationsProvider.notifier).updateLastUsedPort(stationId, port),
  );

  ref.listen<List<ChargingStation>>(stationsProvider, (_, next) {
    notifier.syncStations(next);
  });

  return notifier;
});
