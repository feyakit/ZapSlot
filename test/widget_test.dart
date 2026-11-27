import 'dart:async';

import 'package:charge_quick/models/charging_station.dart';
import 'package:charge_quick/providers/app_providers.dart';
import 'package:charge_quick/providers/station_live_provider.dart';
import 'package:charge_quick/screens/home_screen.dart';
import 'package:charge_quick/screens/rule_settings_screen.dart';
import 'package:charge_quick/services/launch_queue_service.dart';
import 'package:charge_quick/services/notification_service.dart';
import 'package:charge_quick/services/storage_service.dart';
import 'package:charge_quick/theme/app_theme.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopNotificationService extends NotificationService {
  @override
  Future<void> showNetworkRestoredNotification({
    required ChargingStation station,
    required int port,
    required String targetUrl,
    int? displayPort,
  }) async {}

  @override
  Future<void> cancelRecoveryNotification() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late StorageService storage;
  late List<ChargingStation> seedStations;
  late StreamController<List<ConnectivityResult>> connController;
  late StreamController<InternetStatus> netController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    seedStations = await storage.loadStationsOrSeed();
    connController = StreamController<List<ConnectivityResult>>.broadcast();
    netController = StreamController<InternetStatus>.broadcast();
  });

  tearDown(() async {
    await connController.close();
    await netController.close();
  });

  Widget buildTestApp({required bool isOnline}) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialStationsProvider.overrideWithValue(seedStations),
        notificationServiceProvider.overrideWithValue(_NoopNotificationService()),
        launchQueueProvider.overrideWith((ref) {
          return LaunchQueueNotifier(
            storage: storage,
            notifications: ref.read(notificationServiceProvider),
            readStations: () => ref.read(stationsProvider),
            readSettings: () => ref.read(settingsProvider),
            onStationUsed: (stationId, port) => ref
                .read(stationsProvider.notifier)
                .updateLastUsedPort(stationId, port),
            checkInternet: () async => isOnline,
            launchUriCallback: (_) async => true,
            connectivityStream: connController.stream,
            internetStatusStream: netController.stream,
            onScheduleBackground: () async {},
            onCancelBackground: () async {},
          );
        }),
        stationLiveProvider.overrideWith((ref) {
          return StationLiveNotifier(
            readStations: () => ref.read(stationsProvider),
            readIsOnline: () => isOnline,
            readIsForeground: () => true,
            fetchLive: (_, {cachedElectricityFees, cachedPackages}) async => null,
            enableAutoPolling: false,
          );
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const HomeScreen(),
      ),
    );
  }

  testWidgets('HomeScreen displays seed stations and supports offline queueing',
      (tester) async {
    await tester.pumpWidget(buildTestApp(isOnline: false));
    await tester.pumpAndSettle();

    expect(find.text('闪雀'), findsOneWidget);
    expect(find.text('地库离线'), findsOneWidget);
    expect(find.text('W52001715'), findsOneWidget);
    expect(find.text('0'), findsWidgets);

    // 点击第一张卡片的“离线排队 · 0号口”
    await tester.tap(find.text('离线排队 · 0号口'));
    await tester.pumpAndSettle();

    expect(find.text('离线排队中 · 出电梯有网自动唤起'), findsOneWidget);

    // 点击取消排队
    await tester.tap(find.text('取消排队'));
    await tester.pumpAndSettle();

    expect(find.text('离线排队中 · 出电梯有网自动唤起'), findsNothing);

    await tester.scrollUntilVisible(
      find.textContaining('W52001414'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('W52001414'), findsOneWidget);
  });

  testWidgets('online home labels the port buttons as direct payment',
      (tester) async {
    await tester.pumpWidget(buildTestApp(isOnline: true));
    await tester.pumpAndSettle();

    expect(find.text('选号直达支付 · 0号口'), findsOneWidget);
    expect(find.text('外网已畅通 · 点卡展开选口'), findsOneWidget);
    expect(find.text('选号直达支付 · 1号口'), findsNothing);

    // 点击第二张折叠卡：自动展开第二张并自动闭合第一张
    await tester.tap(find.text('B2-B区 2号桩'));
    await tester.pumpAndSettle();

    expect(find.text('选号直达支付 · 1号口'), findsOneWidget);
    expect(find.text('选号直达支付 · 0号口'), findsNothing);
  });

  testWidgets('QuickSerialModal auto-matches station and syncs lastUsedPort',
      (tester) async {
    await tester.pumpWidget(buildTestApp(isOnline: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('输编号直达'));
    await tester.pumpAndSettle();

    // 使用大键盘输入 1414 -> 匹配 W52001414（上次 2号口）
    await tester.tap(find.text('1').last);
    await tester.tap(find.text('4').last);
    await tester.tap(find.text('1').last);
    await tester.tap(find.text('4').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('已匹配保存桩：B2-B区 2号桩'), findsOneWidget);
    expect(find.text('加入离线排队 · 1号口'), findsOneWidget);
  });

  testWidgets('RuleSettingsScreen opens and shows WeiYunChong presets',
      (tester) async {
    await tester.pumpWidget(buildTestApp(isOnline: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.byType(RuleSettingsScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('莱充小程序 · 按插口直达选套餐付款页（默认）'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('莱充小程序 · 按插口直达选套餐付款页（默认）'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('莱充小程序 · 直达选插座页（查看空闲口）'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('莱充小程序 · 直达选插座页（查看空闲口）'), findsOneWidget);
  });

  testWidgets('tapping station card title opens quick rename dialog and saves alias',
      (tester) async {
    await tester.pumpWidget(buildTestApp(isOnline: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('B2-A区 1号桩'));
    await tester.pumpAndSettle();

    expect(find.text('修改名称 · W52001715'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '8.5地下室靠电梯');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('8.5地下室靠电梯'), findsOneWidget);
    expect(find.text('B2-A区 1号桩'), findsNothing);
  });

  testWidgets('tapping alarm button sets charging pickup reminder banner',
      (tester) async {
    await tester.pumpWidget(buildTestApp(isOnline: true));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.alarm_add_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('5 小时后提醒'), findsOneWidget);
    await tester.tap(find.text('5 小时后提醒'));
    await tester.pumpAndSettle();

    expect(find.textContaining('0号口」拔枪'), findsOneWidget);
  });

  testWidgets('footprint tab shows local charging footprint and mini-program button',
      (tester) async {
    await tester.pumpWidget(buildTestApp(isOnline: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('足迹'));
    await tester.pumpAndSettle();

    expect(find.text('足迹与订单'), findsOneWidget);
    expect(find.text('本地充电足迹'), findsOneWidget);
    expect(find.text('打开莱充小程序（查官方订单 / 停充）'), findsOneWidget);
  });
}
