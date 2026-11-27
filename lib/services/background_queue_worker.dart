import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'notification_service.dart';
import 'storage_service.dart';
import 'url_rule_engine.dart';

/// 后台网络恢复 Worker（Android WorkManager + iOS BGTaskScheduler）：
/// 当 App 被系统（如 MIUI/ColorOS/iOS）杀后台后，在网络恢复瞬间通过
/// 1) 联网约束一次性任务（OneOffTask，出电梯恢复信号后尽快触发）
/// 2) 15 分钟周期兜底任务（PeriodicTask，应对厂商延迟调度）
/// 唤醒并推送高优先级本地通知，用户点击通知即可直达充电页。
@pragma('vm:entry-point')
void chargeQuickBackgroundDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final storage = StorageService(prefs);
      final pending = storage.loadPendingQueue();
      if (pending == null) {
        await BackgroundQueueWorker.cancelPendingRecovery();
        return true;
      }

      final stations = await storage.loadStationsOrSeed();
      final station =
          stations.where((s) => s.id == pending.stationId).firstOrNull;
      if (station == null) {
        await storage.clearPendingQueue();
        await BackgroundQueueWorker.cancelPendingRecovery();
        return true;
      }

      final checker = InternetConnection.createInstance(
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
      );

      var isReachable = false;
      try {
        isReachable = await checker.hasInternetAccess;
      } catch (_) {
        isReachable = false;
      }
      if (!isReachable) {
        isReachable = await _quickBackgroundProbe();
      }
      if (!isReachable) {
        // 返回 false 让 Android WorkManager 按退避策略重试，等待真正连通外网。
        return false;
      }

      final settings = storage.loadSettings();
      final uri = UrlRuleEngine.buildTargetUri(station, pending.port, settings);
      if (uri == null) {
        return true;
      }

      final notifications = NotificationService();
      await notifications.initialize();
      await notifications.showNetworkRestoredNotification(
        station: station,
        port: pending.port,
        displayPort: settings.socketNumber(pending.port),
        targetUrl: uri.toString(),
      );
      return true;
    } catch (_) {
      return false;
    }
  });
}

Future<bool> _quickBackgroundProbe() async {
  const urls = [
    'https://connect.rom.miui.com/generate_204',
    'https://wifi.vivo.com.cn/generate_204',
  ];
  for (final raw in urls) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 1200);
    try {
      final req = await client
          .getUrl(Uri.parse(raw))
          .timeout(const Duration(milliseconds: 1200));
      final res = await req.close().timeout(const Duration(milliseconds: 1500));
      await res.drain<void>().timeout(
            const Duration(milliseconds: 500),
            onTimeout: () {},
          );
      if (res.statusCode == 204 || res.statusCode == 200) {
        return true;
      }
    } catch (_) {
      // 尝试下一个探测点
    } finally {
      client.close(force: true);
    }
  }
  return false;
}

/// 后台排队恢复调度封装
class BackgroundQueueWorker {
  const BackgroundQueueWorker._();

  static const String taskIdentifier =
      'com.feyakit.chargeQuick.networkRecovery';
  static const String oneOffUniqueName = 'charge_quick_recovery_one_off';
  static const String periodicUniqueName = 'charge_quick_recovery_periodic';

  static bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> initialize() async {
    if (!_isMobilePlatform) return;
    try {
      await Workmanager().initialize(chargeQuickBackgroundDispatcher);
    } catch (_) {
      // 测试环境或不支持的平台静默降级
    }
  }

  /// 入队后注册后台恢复任务：联网一次性任务 + 15 分钟周期兜底任务。
  static Future<void> schedulePendingRecovery() async {
    if (!_isMobilePlatform) return;
    try {
      await Workmanager().registerOneOffTask(
        oneOffUniqueName,
        taskIdentifier,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(seconds: 15),
        constraints: Constraints(networkType: NetworkType.connected),
      );
      await Workmanager().registerPeriodicTask(
        periodicUniqueName,
        taskIdentifier,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {
      // 平台异常时不阻断主流程
    }
  }

  /// 任务完成或取消后清理全部后台调度。
  static Future<void> cancelPendingRecovery() async {
    if (!_isMobilePlatform) return;
    try {
      await Workmanager().cancelByUniqueName(oneOffUniqueName);
      await Workmanager().cancelByUniqueName(periodicUniqueName);
    } catch (_) {
      // 静默忽略
    }
  }
}
