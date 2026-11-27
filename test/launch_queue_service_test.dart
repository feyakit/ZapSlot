import 'dart:async';
import 'dart:convert';

import 'package:charge_quick/models/app_settings.dart';
import 'package:charge_quick/models/charging_station.dart';
import 'package:charge_quick/providers/app_providers.dart';
import 'package:charge_quick/providers/charging_history_provider.dart';
import 'package:charge_quick/services/launch_queue_service.dart';
import 'package:charge_quick/services/notification_service.dart';
import 'package:charge_quick/services/station_lookup_service.dart';
import 'package:charge_quick/services/storage_service.dart';
import 'package:charge_quick/services/url_rule_engine.dart';
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
    int? displayPort,
  }) async {
    shown.add({
      'stationId': station.id,
      'serialNumber': station.serialNumber,
      'port': port,
      'displayPort': displayPort ?? port,
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
        'alipays://platformapi/startapp?appId=2019012363098597&page=pagesEbike%2Fcommodity%2Fcommodity%3Fdevice_no%3DW52001414%26gun_num%3D7%26from%3DebikePile',
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
        'alipays://platformapi/startapp?appId=2019012363098597&page=pagesEbike%2Fcommodity%2Fcommodity%3Fdevice_no%3DW52001715%26gun_num%3D8%26from%3DebikePile',
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

    test('background network recovery then returning to foreground auto-launches pending task',
        () async {
      final notifier = createNotifier();
      await notifier.initialize();
      notifier.setAppInForeground(false);

      final station1414 =
          stations.firstWhere((s) => s.serialNumber == 'W52001414');
      await notifier.triggerOrQueue(station1414, 1); // 0号口
      expect(notifier.state.hasPendingTask, isTrue);

      // 后台期间恢复网络：仅发通知，不拉起
      isOnlineFlag = true;
      internetController.add(InternetStatus.connected);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifications.shown.length, 1);
      expect(notifications.shown.first['displayPort'], 0);
      expect(launchedUris, isEmpty);
      expect(notifier.state.hasPendingTask, isTrue);

      // 用户未点通知，直接解锁回到闪雀前台 -> 应自动补拉起
      notifier.setAppInForeground(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(launchedUris.length, 1);
      expect(launchedUris.single.toString(), contains('device_no%3DW52001414'));
      expect(launchedUris.single.toString(), contains('gun_num%3D0'));
      expect(notifier.state.hasPendingTask, isFalse);
      expect(storage.loadPendingQueue(), isNull);

      notifier.dispose();
    });

    test('connectivity drop after being online invalidates cache and queues offline in garage',
        () async {
      isOnlineFlag = true;
      final notifier = createNotifier();
      await notifier.initialize();
      expect(notifier.state.isOnline, isTrue);

      // 模拟走进地库：网络切换且外网不可达
      isOnlineFlag = false;
      connectivityController.add([ConnectivityResult.mobile]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final station1715 =
          stations.firstWhere((s) => s.serialNumber == 'W52001715');
      final outcome = await notifier.triggerOrQueue(station1715, 5);
      expect(outcome, QueueActionOutcome.queuedOffline);
      expect(notifier.state.hasPendingTask, isTrue);
      expect(launchedUris, isEmpty);
      expect(bgScheduleCount, 1);

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

    test('StationLookupService MD5 signature and device_name cleaning', () {
      expect(
        StationLookupService.md5Hex('abc'),
        '900150983cd24fb0d6963f7d28e17f72',
      );
      expect(
        StationLookupService.cleanDeviceName(
          '苏州·香滨水岸8.4地下室、W52001414',
          'W52001414',
        ),
        '苏州·香滨水岸8.4地下室',
      );
      expect(
        StationLookupService.isDefaultPlaceholderAlias('车库桩 1414', 'W52001414'),
        isTrue,
      );
      expect(
        StationLookupService.isDefaultPlaceholderAlias('8.4地下室靠电梯', 'W52001414'),
        isFalse,
      );
    });

    test('autoFillMissingAddresses replaces placeholder alias and preserves custom alias',
        () async {
      final notifier = StationsNotifier(
        storage,
        stations,
        fetchLocation: (sn) async {
          if (sn == 'W52009999') {
            return const StationLocationInfo(
              displayName: '苏州·香滨水岸8.6地下室',
              fullAddress: '苏州·香滨水岸8.6地下室（苏州市吴中区）',
            );
          }
          if (sn == 'W52001715') {
            return const StationLocationInfo(
              displayName: '苏州·香滨水岸8.5地下室',
              fullAddress: '苏州·香滨水岸8.5地下室（苏州市吴中区）',
            );
          }
          return null;
        },
      );

      // 模拟地库无网时新增桩（带默认占位名）
      await notifier.collectScannedStation(
        serialNumber: 'W52009999',
        rawUrl: 'http://weixin.weiyunchong.com/payQRcode.html?device_no=W52009999',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final newStation =
          notifier.state.firstWhere((s) => s.serialNumber == 'W52009999');
      expect(newStation.alias, '苏州·香滨水岸8.6地下室');
      expect(newStation.address, '苏州·香滨水岸8.6地下室（苏州市吴中区）');

      // 手动补全已有自定义别名的桩：只补 address，不覆盖用户别名
      await notifier.autoFillMissingAddresses();
      final customStation =
          notifier.state.firstWhere((s) => s.serialNumber == 'W52001715');
      expect(customStation.alias, 'B2-A区 1号桩');
      expect(customStation.address, '苏州·香滨水岸8.5地下室（苏州市吴中区）');

      notifier.dispose();
    });

    test('parseGunStatuses, formatPackageLabel, and pinStationToTop work properly',
        () async {
      final parsed = StationLookupService.parseGunStatuses([
        {'gun_num': '0', 'work_status': '1'},
        {'gun_num': '1', 'work_status': '2'},
        {'gun_num': '2', 'work_status': '3'},
      ]);
      expect(parsed[1], GunWorkStatus.idle);
      expect(parsed[2], GunWorkStatus.busy);
      expect(parsed[3], GunWorkStatus.fault);

      expect(
        StationLookupService.formatPackageLabel({
          'charge_price': 2,
          'charge_duration': '600',
        }),
        '2元/10h',
      );

      final notifier = StationsNotifier(storage, stations);
      final secondId = notifier.state[1].id;
      await notifier.pinStationToTop(secondId);
      expect(notifier.state.first.id, secondId);

      final customGunNums = StationLookupService.parseGunNums([
        {'gun_num': '1', 'work_status': '1'},
        {'gun_num': '2', 'work_status': '2'},
        {'gun_num': '5', 'work_status': '1'},
      ]);
      expect(customGunNums, ['1', '2', '5']);
      final oddStation = stations.first.copyWith(
        portCount: 3,
        gunNums: customGunNums,
      );
      expect(oddStation.socketLabel(3, 0), '5');
      final uri = UrlRuleEngine.buildTargetUri(oddStation, 3, settings);
      expect(uri.toString(), contains('gun_num%3D5'));

      notifier.dispose();
    });

    test('ChargingHistoryNotifier records and clears local charging footprints',
        () async {
      final historyNotifier = ChargingHistoryNotifier(storage);
      expect(historyNotifier.state, isEmpty);

      await historyNotifier.recordLaunch(
        station: stations.first,
        socketLabel: '7',
      );
      expect(historyNotifier.state.length, 1);
      expect(historyNotifier.state.first.socketLabel, '7');
      expect(storage.loadChargingHistory().length, 1);

      await historyNotifier.clearAll();
      expect(historyNotifier.state, isEmpty);
      expect(storage.loadChargingHistory(), isEmpty);
      historyNotifier.dispose();
    });
  });
}
