import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';
import '../models/charging_station.dart';
import 'ad_skip_service.dart';
import 'background_queue_worker.dart';
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
    Future<bool> Function()? checkInternet,
    Future<bool> Function(Uri uri)? launchUriCallback,
    Stream<List<ConnectivityResult>>? connectivityStream,
    Stream<InternetStatus>? internetStatusStream,
    Future<void> Function()? onScheduleBackground,
    Future<void> Function()? onCancelBackground,
    bool autoInit = true,
  })  : _storage = storage,
        _notifications = notifications,
        _readStations = readStations,
        _readSettings = readSettings,
        _onStationUsed = onStationUsed,
        _checkInternetOverride = checkInternet,
        _launchUriOverride = launchUriCallback,
        _connectivityStreamOverride = connectivityStream,
        _internetStatusStreamOverride = internetStatusStream,
        _scheduleBackground =
            onScheduleBackground ?? BackgroundQueueWorker.schedulePendingRecovery,
        _cancelBackground =
            onCancelBackground ?? BackgroundQueueWorker.cancelPendingRecovery,
        _internetChecker = checkInternet == null && internetStatusStream == null
            ? InternetConnection.createInstance(
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
              )
            : null,
        super(const LaunchQueueState()) {
    if (autoInit) {
      unawaited(initialize());
    }
  }

  final StorageService _storage;
  final NotificationService _notifications;
  final List<ChargingStation> Function() _readStations;
  final AppSettings Function() _readSettings;
  final Future<void> Function(String stationId, int port) _onStationUsed;
  final Future<bool> Function()? _checkInternetOverride;
  final Future<bool> Function(Uri uri)? _launchUriOverride;
  final Stream<List<ConnectivityResult>>? _connectivityStreamOverride;
  final Stream<InternetStatus>? _internetStatusStreamOverride;
  final Future<void> Function() _scheduleBackground;
  final Future<void> Function() _cancelBackground;
  final InternetConnection? _internetChecker;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<InternetStatus>? _internetSub;
  bool _isTriggeringRecovery = false;
  DateTime? _lastOnlineConfirmedAt;

  /// 在线热路径窗口：30 秒内确认过外网连通就直接拉起，不再重复探测。
  static const Duration _onlineFreshWindow = Duration(minutes: 5);

  bool get _isOnlineFresh {
    final at = _lastOnlineConfirmedAt;
    if (!state.isOnline || at == null) return false;
    return DateTime.now().difference(at) < _onlineFreshWindow;
  }

  /// 轻量探针：单个国内 204 探测点、800ms 超时，用于点按时的即时判定。
  Future<bool> _quickProbe() async {
    final override = _checkInternetOverride;
    if (override != null) return override();
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final request = await client
          .getUrl(Uri.parse('https://connect.rom.miui.com/generate_204'))
          .timeout(const Duration(milliseconds: 800));
      final response = await request
          .close()
          .timeout(const Duration(milliseconds: 1200));
      await response.drain<void>().timeout(
            const Duration(milliseconds: 500),
            onTimeout: () {},
          );
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> initialize() async {
    _restorePersistedQueue();

    final connStream =
        _connectivityStreamOverride ?? Connectivity().onConnectivityChanged;
    _connectivitySub = connStream.listen((results) {
      if (!mounted) return;
      final hasInterface = results.any((r) => r != ConnectivityResult.none);
      if (!hasInterface) {
        _handleNetworkTransition(false);
      } else {
        unawaited(refreshNetworkStatus());
      }
    });

    final netStream =
        _internetStatusStreamOverride ?? _internetChecker?.onStatusChange;
    if (netStream != null) {
      _internetSub = netStream.listen((status) {
        if (!mounted) return;
        _handleNetworkTransition(status == InternetStatus.connected);
      });
    }

    // 冷启动只同步网络状态，不自动甩出旧排队任务以防误触；
    // 若有残留排队任务，主页横幅会显示“立即唤醒”按钮由用户手动确认。
    await refreshNetworkStatus(triggerRecovery: false);
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

    if (!mounted) return;
    state = state.copyWith(
      pendingStation: matched,
      pendingPort: record.port,
      queuedAt: record.queuedAt,
      statusMessage: '已恢复上次离线排队：${matched.alias} (${_readSettings().socketNumber(record.port)}号口)',
    );
  }

  /// 主动检测真实外网连通性（防止地库伪 Wi-Fi 误判为在线）。
  Future<bool> refreshNetworkStatus({bool triggerRecovery = true}) async {
    if (!mounted) return false;
    state = state.copyWith(isChecking: true);
    try {
      var reachable = false;
      if (_checkInternetOverride != null) {
        reachable = await _checkInternetOverride();
      } else {
        // 第三方检测库在部分 ROM 上会抛异常（SocketException/TLS）而不是返回 false，
        // 单独 try 住，保证总能落到自带的 HTTPS 探针，避免"明明在线却显示离线"。
        try {
          reachable =
              await (_internetChecker?.hasInternetAccess ?? Future.value(false));
        } catch (_) {
          reachable = false;
        }
        if (!reachable) {
          reachable = await _quickProbe();
        }
      }
      if (!mounted) return reachable;
      _handleNetworkTransition(reachable, triggerRecovery: triggerRecovery);
      return reachable;
    } catch (_) {
      if (mounted) {
        _handleNetworkTransition(false, triggerRecovery: triggerRecovery);
      }
      return false;
    } finally {
      if (mounted) {
        state = state.copyWith(isChecking: false);
      }
    }
  }

  void _handleNetworkTransition(
    bool nextIsOnline, {
    bool triggerRecovery = true,
  }) {
    if (!mounted) return;
    final wasOnline = state.isOnline;
    if (nextIsOnline) {
      _lastOnlineConfirmedAt = DateTime.now();
    } else {
      _lastOnlineConfirmedAt = null;
    }
    if (state.isOnline != nextIsOnline || state.isChecking) {
      state = state.copyWith(isOnline: nextIsOnline, isChecking: false);
    }

    if (triggerRecovery &&
        !wasOnline &&
        nextIsOnline &&
        state.hasPendingTask) {
      unawaited(_onNetworkRecoveredWithPendingTask());
    }
  }

  Future<void> _onNetworkRecoveredWithPendingTask() async {
    if (_isTriggeringRecovery || !mounted) return;
    final station = state.pendingStation;
    final port = state.pendingPort;
    if (station == null || port == null) return;

    _isTriggeringRecovery = true;
    try {
      final settings = _readSettings();
      final uri = UrlRuleEngine.buildTargetUri(station, port, settings);
      if (uri == null) {
        if (mounted) {
          state = state.copyWith(
            statusMessage: '目标链接格式无效，请检查规则设置',
          );
        }
        return;
      }

      // 无论前后台都先发高优先级本地通知，确保锁屏/后台切换时用户点一下即可直达。
      await _notifications.showNetworkRestoredNotification(
        station: station,
        port: port,
        targetUrl: uri.toString(),
      );

      if (!mounted) return;
      if (state.isAppInForeground && settings.autoLaunchInForeground) {
        final launched = await _launchUri(uri);
        if (!mounted) return;
        if (launched) {
          await _storage.clearPendingQueue();
          await _cancelBackground();
          state = state.copyWith(
            clearPendingStation: true,
            clearPendingPort: true,
            clearQueuedAt: true,
            lastAttemptedUrl: uri.toString(),
            statusMessage: '网络已恢复，已自动唤起 ${station.serialNumber} (${settings.socketNumber(port)}号口)',
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

  /// 一键直达或离线排队：在线立刻拉起外部 App（选号直达支付），离线持久化排队并注册后台恢复任务。
  Future<QueueActionOutcome> triggerOrQueue(
    ChargingStation station,
    int port,
  ) async {
    final safePort = port.clamp(1, 12);
    await _onStationUsed(station.id, safePort);

    final settings = _readSettings();
    final uri = UrlRuleEngine.buildTargetUri(station, safePort, settings);
    if (uri == null) {
      if (mounted) {
        state = state.copyWith(
          statusMessage: '无法生成有效链接，请先检查规则模板或桩号',
        );
      }
      return QueueActionOutcome.launchFailed;
    }

    // 热路径：最近 30 秒内已确认在线时跳过探针，点按即刻拉起支付宝直达支付页。
    if (!_isOnlineFresh) {
      final online = await _quickProbe();
      if (mounted) {
        _handleNetworkTransition(online, triggerRecovery: false);
      }
      if (!online) {
        return _enqueueOffline(station, safePort, uri);
      }
    }

    final launched = await _launchUri(uri);
    if (!mounted) {
      return launched
          ? QueueActionOutcome.launchedImmediately
          : QueueActionOutcome.launchFailed;
    }
    if (launched) {
      // 拉起成功说明网络与目标 App 都可用，记一次"刚确认在线"，下次点按直接走热路径。
      _lastOnlineConfirmedAt = DateTime.now();
      await _storage.clearPendingQueue();
      await _cancelBackground();
      await _notifications.cancelRecoveryNotification();
      if (!mounted) return QueueActionOutcome.launchedImmediately;
      state = state.copyWith(
        isOnline: true,
        isChecking: false,
        clearPendingStation: true,
        clearPendingPort: true,
        clearQueuedAt: true,
        lastAttemptedUrl: uri.toString(),
        statusMessage: '已直达 ${station.serialNumber} (${settings.socketNumber(safePort)}号口)',
      );
      return QueueActionOutcome.launchedImmediately;
    }

    // 拉起失败：若其实离线（地库伪 Wi-Fi）则转到离线排队，否则提示 Scheme 不可用。
    final onlineNow = await _quickProbe();
    if (!onlineNow) {
      return _enqueueOffline(station, safePort, uri);
    }
    if (mounted) {
      state = state.copyWith(
        lastAttemptedUrl: uri.toString(),
        statusMessage:
            '未能唤起外部应用 (${uri.scheme})，请确认已安装支付宝/微信或检查规则',
      );
    }
    return QueueActionOutcome.launchFailed;
  }

  /// 离线入队：持久化任务并注册后台网络恢复任务。
  Future<QueueActionOutcome> _enqueueOffline(
    ChargingStation station,
    int port,
    Uri uri,
  ) async {
    await _storage.savePendingQueue(stationId: station.id, port: port);
    await _scheduleBackground();
    if (!mounted) return QueueActionOutcome.queuedOffline;
    state = state.copyWith(
      pendingStation: station.copyWith(lastUsedPort: port),
      pendingPort: port,
      queuedAt: DateTime.now(),
      lastAttemptedUrl: uri.toString(),
      statusMessage: '已加入地库离线排队：${station.serialNumber} · ${_readSettings().socketNumber(port)}号口',
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
    if (!mounted) return launched;
    if (launched) {
      await _storage.clearPendingQueue();
      await _cancelBackground();
      await _notifications.cancelRecoveryNotification();
      if (!mounted) return true;
      state = state.copyWith(
        clearPendingStation: true,
        clearPendingPort: true,
        clearQueuedAt: true,
        lastAttemptedUrl: uri.toString(),
        statusMessage: '已唤起 ${station.serialNumber} (${_readSettings().socketNumber(port)}号口)',
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
    await _cancelBackground();
    await _notifications.cancelRecoveryNotification();
    if (!mounted) return;
    state = state.copyWith(
      clearPendingStation: true,
      clearPendingPort: true,
      clearQueuedAt: true,
      statusMessage: '已取消离线排队',
    );
  }

  /// 同步充电桩列表变更（例如用户修改了正在排队的桩别名/模板或删除了该桩）。
  void syncStations(List<ChargingStation> stations) {
    if (!mounted) return;
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
    if (!mounted) return;
    state = state.copyWith(isAppInForeground: isForeground);
    if (isForeground) {
      unawaited(refreshNetworkStatus());
    }
  }

  void clearStatusMessage() {
    if (!mounted) return;
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
            await _cancelBackground();
            if (!mounted) return;
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

    if (mounted && state.hasPendingTask) {
      await retryPendingNow();
    }
  }

  Future<bool> _launchUri(Uri uri) async {
    try {
      if (_launchUriOverride != null) {
        return await _launchUriOverride(uri);
      }
      if (uri.scheme.toLowerCase() == 'alipays') {
        await AdSkipService.armForAlipayLaunch();
      }
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
