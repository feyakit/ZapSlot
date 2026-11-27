import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/charging_station.dart';

/// 本地高优先级通知服务：当出电梯网络恢复时推送直达提醒，点击即可触发外部跳转。
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'charge_quick_network_recovery';
  static const String channelName = '网络恢复直达提醒';
  static const String channelDescription =
      '地下车库排队任务在网络恢复时推送高优先级通知，点击立即打开充电页面';
  static const int _recoveryNotificationId = 1001;
  static const int _reminderNotificationId = 1002;

  void Function(String? payload)? _onNotificationTap;
  bool _initialized = false;

  Future<String?> initialize({
    void Function(String? payload)? onNotificationTap,
  }) async {
    _onNotificationTap = onNotificationTap;
    if (_initialized) return null;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _onNotificationTap?.call(response.payload);
      },
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin.requestNotificationsPermission();
    }

    _initialized = true;

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      return launchDetails.notificationResponse?.payload;
    }
    return null;
  }

  void setTapHandler(void Function(String? payload) handler) {
    _onNotificationTap = handler;
  }

  Future<void> showNetworkRestoredNotification({
    required ChargingStation station,
    required int port,
    required String targetUrl,
    int? displayPort,
  }) async {
    final shownPort = displayPort ?? port;
    final payload = jsonEncode({
      'stationId': station.id,
      'serialNumber': station.serialNumber,
      'port': port,
      'url': targetUrl,
    });

    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      ticker: '网络已恢复，点击直达充电桩',
      category: AndroidNotificationCategory.alarm,
      autoCancel: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    await _plugin.show(
      _recoveryNotificationId,
      '网络已恢复：点击直达充电桩 ${station.serialNumber}',
      '${station.alias} · $shownPort号插座，点击立即唤起充电',
      details,
      payload: payload,
    );
  }

  Future<void> showChargingReminderNotification({
    required String stationName,
    required String portLabel,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.max,
      ticker: '闪雀提醒：小电驴该拔电啦',
      category: AndroidNotificationCategory.alarm,
      autoCancel: true,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
    );

    final suffix = portLabel.isEmpty ? '' : ' · $portLabel号口';
    await _plugin.show(
      _reminderNotificationId,
      '闪雀拔电提醒：$stationName',
      '充电定时已到$suffix，记得下楼给电驴拔电',
      details,
    );
  }

  Future<void> cancelRecoveryNotification() async {
    await _plugin.cancel(_recoveryNotificationId);
  }

  Future<void> cancelChargingReminderNotification() async {
    await _plugin.cancel(_reminderNotificationId);
  }
}
