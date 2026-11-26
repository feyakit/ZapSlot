import 'dart:async';
import 'dart:convert';

import 'package:charge_quick/models/app_settings.dart';
import 'package:charge_quick/models/charging_station.dart';
import 'package:charge_quick/providers/app_providers.dart';
import 'package:charge_quick/services/launch_queue_service.dart';
import 'package:charge_quick/services/notification_service.dart';
import 'package:charge_quick/services/storage_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotificationService extends NotificationService {
  final List<Map<String, dynamic>> shown = [];
  int cancelCount = 0;

  @override
  Future<void> showNetworkRestoredNotification({
    required ChargingStation station,
    required int port,
    required String targetUrl,
  }) async {
    shown.add({
      'stationId': station.id,
      'serialNumber': station.serialNumber,
      'port': port,
      'url': targetUrl,
    });
  }

  @override
  Future<void> cancelRecoveryNotification() async {
    cancelCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late _FakeNotificationService notifications;
  late List<ChargingStation> stations;
  late AppSettings settings;
  late StreamController<List<ConnectivityResult>> connectivityController;
  late StreamController<InternetStatus> internetController;
  late List<Uri> launchedUris;
  late bool isOnlineFlag;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    notifications = _FakeNotificationService();
    stations = await storage.loadStationsOrSeed();
    settings = const AppSettings();
    connectivityController = StreamController<List<ConnectivityResult>>.broadcast();
    internetController = StreamController<InternetStatus>.broadcast();
    launchedUris = [];
    isOnlineFlag = false;
  });

  tearDown(() async {
    await connectivityController.close();
    await internetController.close();
  });

  LaunchQueueNotifier createNotifier() {
    return LaunchQueueNotifier(
      storage: storage,
      notifications: notifications,
      readStations: () => stations,
      readSettings: () => settings,
      onStationUsed: (stationId, port) async {},
      checkInternet: () async => isOnlineFlag,
      launchUriCallback: (uri) async {
        launchedUris.add(uri);
        return true;
      },
      connectivityStream: connectivityController.stream,
      internetStatusStream: internetController.stream,
      autoInit: false,
    );
  }

  group('LaunchQueueNotifier & StorageService (real QR stations)', () {
    test('seed stations contain real WeiYunChong QR URLs for W52001715 & W52001414',
        () {
      expect(stations.length, 2);
      expect(stations[0].serialNumber, 'W52001715');
      expect(
        stations[0].rawUrl,
        'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52001715',
      );
      expect(stations[1].serialNumber, 'W52001414');
      expect(
        stations[1].rawUrl,
        'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52001414',
      );
    });

    test('queues offline in garage and auto-launches in foreground when network recovers',
        () async {
      final notifier = createNotifier();
      await notifier.initialize();
      expect(notifier.state.isOnline, isFalse);

      final station1414 =
          stations.firstWhere((s) => s.serialNumber == 'W52001414');
      final outcome = await notifier.triggerOrQueue(station1414, 8);
      expect(outcome, QueueActionOutcome.queuedOffline);
      expect(notifier.state.hasPendingTask, isTrue);
      expect(storage.loadPendingQueue()?.stationId, station1414.id);
      expect(storage.loadPendingQueue()?.port, 8);
      expect(launchedUris, isEmpty);

      // 模拟坐电梯上楼网络恢复（App 在前台）
      isOnlineFlag = true;
      internetController.add(InternetStatus.connected);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifications.shown.length, 1);
      expect(notifications.shown.first['serialNumber'], 'W52001414');
      expect(launchedUris.length, 1);
      expect(
        launchedUris.first.toString(),
        'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3DW52001414',
      );
      expect(notifier.state.hasPendingTask, isFalse);
      expect(storage.loadPendingQueue(), isNull);

      notifier.dispose();
    });

    test('sends notification without auto-launch in background, then launches on notification tap',
        () async {
      final notifier = createNotifier();
      await notifier.initialize();
      notifier.setAppInForeground(false);

      final station1715 =
          stations.firstWhere((s) => s.serialNumber == 'W52001715');
      await notifier.triggerOrQueue(station1715, 9);
      expect(notifier.state.hasPendingTask, isTrue);

      isOnlineFlag = true;
      internetController.add(InternetStatus.connected);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifications.shown.length, 1);
      expect(launchedUris, isEmpty);
      expect(notifier.state.hasPendingTask, isTrue);

      final payload = jsonEncode(notifications.shown.first);
      await notifier.handleNotificationPayload(payload);

      expect(launchedUris.length, 1);
      expect(
        launchedUris.first.toString(),
        'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3DW52001715',
      );
      expect(notifier.state.hasPendingTask, isFalse);

      notifier.dispose();
    });

    test('triggerOrQueue when network already recovered does NOT double-launch stale pending task',
        () async {
      final notifier = createNotifier();
      await notifier.initialize();

      final station1414 =
          stations.firstWhere((s) => s.serialNumber == 'W52001414');
      final station1715 =
          stations.firstWhere((s) => s.serialNumber == 'W52001715');

      // 先离线排队 1414
      final first = await notifier.triggerOrQueue(station1414, 8);
      expect(first, QueueActionOutcome.queuedOffline);

      // 此时外网已恢复，用户直接点击另一台桩 1715
      isOnlineFlag = true;
      final second = await notifier.triggerOrQueue(station1715, 9);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(second, QueueActionOutcome.launchedImmediately);
      expect(launchedUris.length, 1);
      expect(launchedUris.single.toString(), contains('W52001715'));
      expect(notifier.state.hasPendingTask, isFalse);

      notifier.dispose();
    });

    test('StationsNotifier preserves customDeepLinkTemplate on re-scan',
        () async {
      final stationsNotifier = StationsNotifier(storage, stations);
      final target = stations.first;

      await stationsNotifier.upsertStation(
        id: target.id,
        alias: target.alias,
        serialNumber: target.serialNumber,
        rawUrl: target.rawUrl,
        customDeepLinkTemplate: 'weixin://dl/business/?t=CUSTOM_TICKET',
        lastUsedPort: 5,
      );
      expect(
        stationsNotifier.state.first.customDeepLinkTemplate,
        'weixin://dl/business/?t=CUSTOM_TICKET',
      );

      // 模拟离线扫描页重新扫到同一台桩
      await stationsNotifier.upsertStation(
        id: target.id,
        alias: target.alias,
        serialNumber: target.serialNumber,
        rawUrl: target.rawUrl,
        preserveCustomTemplateIfNull: true,
        lastUsedPort: 6,
      );
      expect(
        stationsNotifier.state.first.customDeepLinkTemplate,
        'weixin://dl/business/?t=CUSTOM_TICKET',
      );
      expect(stationsNotifier.state.first.lastUsedPort, 6);

      stationsNotifier.dispose();
    });
  });
}
