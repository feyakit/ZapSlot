import 'dart:async';

import 'package:charge_quick/models/charging_station.dart';
import 'package:charge_quick/providers/app_providers.dart';
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

    expect(find.text('快充直达'), findsOneWidget);
    expect(find.text('地库离线模式'), findsOneWidget);
    expect(find.text('W52001715'), findsOneWidget);
    expect(find.text('W52001414'), findsOneWidget);
    expect(find.text('备忘插座号（仅本地记录，目标页内选口）'), findsNWidgets(2));

    // 点击第一张卡片的“离线排队 · 1号口”
    await tester.tap(find.text('离线排队 · 1号口'));
    await tester.pumpAndSettle();

    expect(find.text('离线排队中 · 出电梯有网自动唤起'), findsOneWidget);

    // 点击取消排队
    await tester.tap(find.text('取消排队'));
    await tester.pumpAndSettle();

    expect(find.text('离线排队中 · 出电梯有网自动唤起'), findsNothing);
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
    expect(find.text('加入离线排队 · 2号口'), findsOneWidget);
  });

  testWidgets('RuleSettingsScreen opens and shows WeiYunChong presets',
      (tester) async {
    await tester.pumpWidget(buildTestApp(isOnline: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('规则设置'));
    await tester.pumpAndSettle();

    expect(find.byType(RuleSettingsScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('通用原始码 · 支付宝直达（默认，最稳妥）'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('通用原始码 · 支付宝直达（默认，最稳妥）'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('微云充 · 原码保留参数 + 传插座号直达支付页'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('微云充 · 原码保留参数 + 传插座号直达支付页'), findsOneWidget);
  });
}
