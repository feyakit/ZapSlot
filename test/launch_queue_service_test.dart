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
  late int bgScheduleCount;
  late int bgCancelCount;

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
    bgScheduleCount = 0;
    bgCancelCount = 0;
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
      onScheduleBackground: () async {
        bgScheduleCount++;
      },
      onCancelBackground: () async {
        bgCancelCount++;
      },
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

    test('queues offline in garage, schedules WorkManager, and auto-launches when network recovers',
        () async {
      final notifier = createNotifier();
      await notifier.initialize();
      expect(notifier.state.isOnline, isFalse);

      final station1414 =
          stations.firstWhere((s) => s.serialNumber == 'W52001414');
      final outcome = await notifier.triggerOrQueue(station1414, 8);
      expect(outcome, QueueActionOutcome.queuedOffline);
      expect(notifier.state.hasPendingTask, isTrue);
      expect(bgScheduleCount, 1);
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
        'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3DW52001414%26gun_num%3D7',
      );
      expect(bgCancelCount, 1);
      expect(notifier.state.hasPendingTask, isFalse);
      expect(storage.loadPendingQueue(), isNull);

      notifier.dispose();
    });

    test('cold start with leftover pending task while online does NOT auto-launch misfire',
        () async {
      final station1715 =
          stations.firstWhere((s) => s.serialNumber == 'W52001715');
      await storage.savePendingQueue(stationId: station1715.id, port: 4);

      isOnlineFlag = true;
      final notifier = createNotifier();
      await notifier.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifier.state.isOnline, isTrue);
      expect(notifier.state.hasPendingTask, isTrue);
      expect(launchedUris, isEmpty);
      expect(notifications.shown, isEmpty);

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
        'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3DW52001715%26gun_num%3D8',
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

    test('online tap launches Alipay deep link directly without queueing',
        () async {
      final notifier = createNotifier();
      await notifier.initialize();
      isOnlineFlag = true;

      final station = stations.firstWhere((s) => s.serialNumber == 'W52001715');
      final outcome = await notifier.triggerOrQueue(station, 3);

      expect(outcome, QueueActionOutcome.launchedImmediately);
      expect(launchedUris.length, 1);
      expect(launchedUris.single.toString(), contains('gun_num%3D2'));
      expect(bgScheduleCount, 0);
      expect(notifier.state.hasPendingTask, isFalse);
      expect(storage.loadPendingQueue(), isNull);
      expect(notifier.state.statusMessage, contains('已直达'));

      notifier.dispose();
    });

    test('collectScannedStation auto-adds new QR and keeps config on rescan',
        () async {
      final notifier = StationsNotifier(storage, stations);
      final original = stations.first;
      await notifier.upsertStation(
        id: original.id,
        alias: 'B2-A区 1号桩',
        serialNumber: original.serialNumber,
        rawUrl: original.rawUrl,
        customDeepLinkTemplate: 'weixin://dl/business/?t=abc',
        lastUsedPort: 6,
      );

      final rescanned = await notifier.collectScannedStation(
        serialNumber: 'w52001715',
        rawUrl:
            'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52001715&sign=x',
      );
      expect(rescanned.alias, 'B2-A区 1号桩');
      expect(rescanned.lastUsedPort, 6);
      expect(rescanned.customDeepLinkTemplate, 'weixin://dl/business/?t=abc');
      expect(rescanned.rawUrl, contains('sign=x'));
      expect(notifier.state.length, stations.length);

      final added = await notifier.collectScannedStation(
        serialNumber: 'W52009999',
        rawUrl:
            'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52009999',
      );
      expect(added.alias, '车库桩 9999');
      expect(added.serialNumber, 'W52009999');
      expect(notifier.state.first.id, added.id);
      expect(notifier.state.length, stations.length + 1);
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
