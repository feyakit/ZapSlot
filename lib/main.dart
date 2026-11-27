import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/app_settings.dart';
import 'providers/app_providers.dart';
import 'screens/home_screen.dart';
import 'services/background_queue_worker.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 只做首帧必须的准备工作（读本地数据，毫秒级）；
  // WorkManager 初始化与通知权限弹窗放到界面出现之后，避免冷启动被权限框卡住。
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final initialStations = await storage.loadStationsOrSeed();
  final notifications = NotificationService();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialStationsProvider.overrideWithValue(initialStations),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const ChargeQuickApp(),
    ),
  );
}

class ChargeQuickApp extends ConsumerStatefulWidget {
  const ChargeQuickApp({
    super.key,
    this.initialNotificationPayload,
  });

  final String? initialNotificationPayload;

  @override
  ConsumerState<ChargeQuickApp> createState() => _ChargeQuickAppState();
}

class _ChargeQuickAppState extends ConsumerState<ChargeQuickApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final notifications = ref.read(notificationServiceProvider);
    notifications.setTapHandler((payload) {
      ref.read(launchQueueProvider.notifier).handleNotificationPayload(payload);
    });

    // 首帧之后再准备后台任务与通知通道，并补处理"由通知点开冷启动"的情况。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(BackgroundQueueWorker.initialize());
      unawaited(_prepareNotifications(notifications));
    });

    if (widget.initialNotificationPayload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(launchQueueProvider.notifier)
            .handleNotificationPayload(widget.initialNotificationPayload);
      });
    }
  }

  Future<void> _prepareNotifications(NotificationService notifications) async {
    final payload = await notifications.initialize();
    if (!mounted || payload == null || payload.isEmpty) return;
    ref.read(launchQueueProvider.notifier).handleNotificationPayload(payload);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    ref.read(launchQueueProvider.notifier).setAppInForeground(isForeground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themePref = ref.watch(
      settingsProvider.select((s) => s.themePreference),
    );
    final themeMode = switch (themePref) {
      AppThemePreference.system => ThemeMode.system,
      AppThemePreference.light => ThemeMode.light,
      AppThemePreference.dark => ThemeMode.dark,
    };
    return MaterialApp(
      title: '闪雀 ZapSlot',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.15,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeScreen(),
    );
  }
}
