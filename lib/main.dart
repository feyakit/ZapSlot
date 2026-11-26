import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/app_providers.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  final initialStations = await storage.loadStationsOrSeed();

  final notifications = NotificationService();
  final launchPayload = await notifications.initialize();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialStationsProvider.overrideWithValue(initialStations),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: ChargeQuickApp(initialNotificationPayload: launchPayload),
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

    if (widget.initialNotificationPayload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(launchQueueProvider.notifier)
            .handleNotificationPayload(widget.initialNotificationPayload);
      });
    }
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
    return MaterialApp(
      title: '快充直达 ChargeQuick',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
