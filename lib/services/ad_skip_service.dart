import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 无障碍自动跳过支付宝开屏广告桥接服务。
/// 仅在 Android 平台生效，iOS 与测试环境自动静默降级。
class AdSkipService {
  const AdSkipService._();

  static const MethodChannel _channel =
      MethodChannel('com.feyakit.charge_quick/ad_skip');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// 查询用户是否已在系统无障碍设置中启用「闪雀 · 跳过支付宝开屏广告」。
  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    try {
      final enabled = await _channel.invokeMethod<bool>('isEnabled');
      return enabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 打开 Android 系统无障碍设置页。
  static Future<void> openAccessibilitySettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {}
  }

  /// 在拉起 `alipays://` 前开启短暂窗口（默认 6 秒），期间检测到支付宝开屏「跳过」即自动点击。
  static Future<void> armForAlipayLaunch({int durationMs = 6000}) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(
        'armSkipWindow',
        {'durationMs': durationMs},
      );
    } catch (_) {}
  }
}
