import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';
import '../models/charging_station.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'url_rule_engine.dart';

/// 排队触发结果
enum QueueActionOutcome {
  launchedImmediately,
  queuedOffline,
  launchFailed,
}

/// 实时网络与离线排队状态
class LaunchQueueState {
  const LaunchQueueState({
    this.isOnline = false,
    this.isChecking = true,
    this.pendingStation,
    this.pendingPort,
    this.queuedAt,
    this.isAppInForeground = true,
    this.lastAttemptedUrl,
    this.statusMessage,
  });

  final bool isOnline;
  final bool isChecking;
  final ChargingStation? pendingStation;
  final int? pendingPort;
  final DateTime? queuedAt;
  final bool isAppInForeground;
  final String? lastAttemptedUrl;
  final String? statusMessage;

  bool get hasPendingTask => pendingStation != null && pendingPort != null;

  LaunchQueueState copyWith({
    bool? isOnline,
    bool? isChecking,
    ChargingStation? pendingStation,
    bool clearPendingStation = false,
    int? pendingPort,
    bool clearPendingPort = false,
    DateTime? queuedAt,
    bool clearQueuedAt = false,
    bool? isAppInForeground,
    String? lastAttemptedUrl,
    String? statusMessage,
    bool clearStatusMessage = false,
  }) {
    return LaunchQueueState(
      isOnline: isOnline ?? this.isOnline,
      isChecking: isChecking ?? this.isChecking,
      pendingStation: clearPendingStation
          ? null
          : (pendingStation ?? this.pendingStation),
      pendingPort: clearPendingPort ? null : (pendingPort ?? this.pendingPort),
      queuedAt: clearQueuedAt ? null : (queuedAt ?? this.queuedAt),
      isAppInForeground: isAppInForeground ?? this.isAppInForeground,
      lastAttemptedUrl: lastAttemptedUrl ?? this.lastAttemptedUrl,
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
    );
  }
}

/// 网络监听与自动直达队列控制器
class LaunchQueueNotifier extends StateNotifier<LaunchQueueState> {
  LaunchQueueNotifier({
    required StorageService storage,
    required NotificationService notifications,
    required List<ChargingStation> Function() readStations,
    required AppSettings Function() readSettings,
    required Future<void> Function(String stationId, int port) onStationUsed,
  })  : _storage = storage,
        _notifications = notifications,
        _readStations = readStations,
        _readSettings = readSettings,
        _onStationUsed = onStationUsed,
        _internetChecker = InternetConnection.createInstance(
          checkInterval: const Duration(seconds: 3),
          useDefaultOptions: false,
          customCheckOptions: [
            InternetCheckOption(
              uri: Uri.parse('https://connect.rom.miui.com/generate_204'),
              timeout: const Duration(seconds: 2),
            ),
            InternetCheckOption(
              uri: Uri.parse('https://wifi.vivo.com.cn/generate_204'),
              timeout: const Duration(seconds: 2),
            ),
            InternetCheckOption(
              uri: Uri.parse('https://res.wx.qq.com'),
              timeout: const Duration(seconds: 3),
            ),
          ],
        ),
        super(const LaunchQueueState()) {
    _init();
  }

  final StorageService _storage;
  final NotificationService _notifications;
  final List<ChargingStation> Function() _readStations;
  final AppSettings Function() _readSettings;
  final Future<void> Function(String stationId, int port) _onStationUsed;
  final InternetConnection _internetChecker;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<InternetStatus>? _internetSub;
  bool _isTriggeringRecovery = false;

  Future<void> _init() async {
    _restorePersistedQueue();

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      if (!hasInterface) {
        _handleNetworkTransition(false);
      } else {
        unawaited(refreshNetworkStatus());
      }
    });

    _internetSub = _internetChecker.onStatusChange.listen((status) {
      _handleNetworkTransition(status == InternetStatus.connected);
    });

    await refreshNetworkStatus();
  }

  void _restorePersistedQueue() {
    final record = _storage.loadPendingQueue();
    if (record == null) return;

    final stations = _readStations();
    final matched = stations.where((s) => s.id == record.stationId).firstOrNull;
    if (matched == null) {
      unawaited(_storage.clearPendingQueue());
      return;
    }

    state = state.copyWith(
      pendingStation: matched,
      pendingPort: record.port,
      queuedAt: record.queuedAt,
      statusMessage: '已恢复上次离线排队：${matched.alias} (${record.port}号口)',
    );
  }

  /// 主动检测真实外网连通性（防止地库伪 Wi-Fi 误判为在线）。
  Future<bool> refreshNetworkStatus() async {
    state = state.copyWith(isChecking: true);
    try {
      final reachable = await _internetChecker.hasInternetAccess;
      _handleNetworkTransition(reachable);
      return reachable;
    } catch (_) {
      _handleNetworkTransition(false);
      return false;
    } finally {
      if (mounted) {
        state = state.copyWith(isChecking: false);
      }
    }
  }

  void _handleNetworkTransition(bool nextIsOnline) {
    final wasOnline = state.isOnline;
    if (state.isOnline != nextIsOnline || state.isChecking) {
      state = state.copyWith(isOnline: nextIsOnline, isChecking: false);
    }

    if (!wasOnline && nextIsOnline && state.hasPendingTask) {
      unawaited(_onNetworkRecoveredWithPendingTask());
    }
  }

  Future<void> _onNetworkRecoveredWithPendingTask() async {
    if (_isTriggeringRecovery) return;
    final station = state.pendingStation;
    final port = state.pendingPort;
    if (station == null || port == null) return;

    _isTriggeringRecovery = true;
    try {
      final settings = _readSettings();
      final uri = UrlRuleEngine.buildTargetUri(station, port, settings);
      if (uri == null) {
        state = state.copyWith(
          statusMessage: '目标链接格式无效，请检查规则设置',
        );
        return;
      }

      // 无论前后台都先发高优先级本地通知，确保锁屏/后台切换时用户点一下即可直达。
      await _notifications.showNetworkRestoredNotification(
        station: station,
        port: port,
        targetUrl: uri.toString(),
      );

      if (state.isAppInForeground && settings.autoLaunchInForeground) {
        final launched = await _launchUri(uri);
        if (launched) {
          await _storage.clearPendingQueue();
          state = state.copyWith(
            clearPendingStation: true,
            clearPendingPort: true,
            clearQueuedAt: true,
            lastAttemptedUrl: uri.toString(),
            statusMessage: '网络已恢复，已自动唤起 ${station.serialNumber} ($port号口)',
          );
        } else {
          state = state.copyWith(
            lastAttemptedUrl: uri.toString(),
            statusMessage: '网络已恢复，请点击上方“立即唤醒”或系统通知打开充电页',
          );
        }
      } else {
        state = state.copyWith(
          lastAttemptedUrl: uri.toString(),
          statusMessage: '网络已恢复，已发送直达通知',
        );
      }
    } finally {
      _isTriggeringRecovery = false;
    }
  }

  /// 一键直达或离线排队：在线立即拉起外部 App，离线持久化排队。
  Future<QueueActionOutcome> triggerOrQueue(
    ChargingStation station,
    int port,
  ) async {
    final safePort = port.clamp(1, 12);
    await _onStationUsed(station.id, safePort);

    final settings = _readSettings();
    final uri = UrlRuleEngine.buildTargetUri(station, safePort, settings);
    if (uri == null) {
      state = state.copyWith(
        statusMessage: '无法生成有效链接，请先检查规则模板或桩号',
      );
      return QueueActionOutcome.launchFailed;
    }

    // 触发前先做一次快速连通性确认，避免状态过期。
    final currentlyOnline = await refreshNetworkStatus();
    if (currentlyOnline) {
      final launched = await _launchUri(uri);
      if (launched) {
        await _storage.clearPendingQueue();
        await _notifications.cancelRecoveryNotification();
        state = state.copyWith(
          clearPendingStation: true,
          clearPendingPort: true,
          clearQueuedAt: true,
          lastAttemptedUrl: uri.toString(),
          statusMessage: '已拉起 ${station.serialNumber} ($safePort号口)',
        );
        return QueueActionOutcome.launchedImmediately;
      }

      // 某些机型/系统可能未安装对应 Scheme 应用，保留提示但不误入离线队列。
      state = state.copyWith(
        lastAttemptedUrl: uri.toString(),
        statusMessage: '未能唤起外部应用 (${uri.scheme})，请确认已安装微信/支付宝或检查规则',
      );
      return QueueActionOutcome.launchFailed;
    }

    await _storage.savePendingQueue(stationId: station.id, port: safePort);
    state = state.copyWith(
      pendingStation: station.copyWith(lastUsedPort: safePort),
      pendingPort: safePort,
      queuedAt: DateTime.now(),
      lastAttemptedUrl: uri.toString(),
      statusMessage: '已加入地库离线排队：${station.serialNumber} · $safePort号口',
    );
    return QueueActionOutcome.queuedOffline;
  }

  /// 手动立即重试当前排队任务。
  Future<bool> retryPendingNow() async {
    final station = state.pendingStation;
    final port = state.pendingPort;
    if (station == null || port == null) return false;

    final settings = _readSettings();
    final uri = UrlRuleEngine.buildTargetUri(station, port, settings);
    if (uri == null) {
      state = state.copyWith(statusMessage: '目标链接无效，请检查规则设置');
      return false;
    }

    final launched = await _launchUri(uri);
    if (launched) {
      await _storage.clearPendingQueue();
      await _notifications.cancelRecoveryNotification();
      state = state.copyWith(
        clearPendingStation: true,
        clearPendingPort: true,
        clearQueuedAt: true,
        lastAttemptedUrl: uri.toString(),
        statusMessage: '已唤起 ${station.serialNumber} ($port号口)',
      );
      return true;
    }

    state = state.copyWith(
      lastAttemptedUrl: uri.toString(),
      statusMessage: '拉起失败，请确认信号稳定或目标 App 已安装',
    );
    return false;
  }

  Future<void> cancelQueue() async {
    await _storage.clearPendingQueue();
    await _notifications.cancelRecoveryNotification();
    state = state.copyWith(
      clearPendingStation: true,
      clearPendingPort: true,
      clearQueuedAt: true,
      statusMessage: '已取消离线排队',
    );
  }

  /// 同步充电桩列表变更（例如用户修改了正在排队的桩别名/模板或删除了该桩）。
  void syncStations(List<ChargingStation> stations) {
    final pending = state.pendingStation;
    if (pending == null) return;
    final updated = stations.where((s) => s.id == pending.id).firstOrNull;
    if (updated == null) {
      unawaited(cancelQueue());
    } else if (updated != pending) {
      state = state.copyWith(pendingStation: updated);
    }
  }

  void setAppInForeground(bool isForeground) {
    state = state.copyWith(isAppInForeground: isForeground);
    if (isForeground) {
      unawaited(refreshNetworkStatus());
    }
  }

  void clearStatusMessage() {
    state = state.copyWith(clearStatusMessage: true);
  }

  /// 处理用户点击本地通知后的直达跳转。
  Future<void> handleNotificationPayload(String? payload) async {
    if (payload == null || payload.isEmpty) {
      if (state.hasPendingTask) {
        await retryPendingNow();
      }
      return;
    }

    try {
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      final url = decoded['url'] as String?;
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          final launched = await _launchUri(uri);
          if (launched) {
            await _storage.clearPendingQueue();
            state = state.copyWith(
              clearPendingStation: true,
              clearPendingPort: true,
              clearQueuedAt: true,
              lastAttemptedUrl: url,
              statusMessage: '已通过通知直达充电页',
            );
            return;
          }
        }
      }
    } catch (_) {
      // 回退到当前队列任务重试
    }

    if (state.hasPendingTask) {
      await retryPendingNow();
    }
  }

  Future<bool> _launchUri(Uri uri) async {
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _internetSub?.cancel();
    super.dispose();
  }
}
