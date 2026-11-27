import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// 单个探针的检测结果
class ProbeResult {
  const ProbeResult({
    required this.uri,
    required this.host,
    this.statusCode,
    this.elapsedMs,
    this.error,
  });

  final String uri;
  final String host;
  final int? statusCode;
  final int? elapsedMs;
  final String? error;

  /// 只要拿到 HTTP 响应就说明链路通（204/200 是标准探测点，404 等也证明可达）。
  bool get ok => statusCode != null;

  String get summary {
    if (ok) return 'HTTP $statusCode · ${elapsedMs ?? 0}ms';
    if (error != null) return '$error · ${elapsedMs ?? 0}ms';
    return 'HTTP $statusCode · ${elapsedMs ?? 0}ms';
  }
}

/// 现场网络诊断：地库/电梯口排查"明明有信号却提示离线"时使用。
/// 全部走 HTTPS（Android 9+ 默认禁止明文 HTTP，探针必须用 https）。
class NetworkDiagnostics {
  const NetworkDiagnostics._();

  static const List<String> probeUrls = [
    'https://connect.rom.miui.com/generate_204',
    'https://wifi.vivo.com.cn/generate_204',
    'https://res.wx.qq.com',
  ];

  static Future<List<ProbeResult>> runProbes({
    Duration timeout = const Duration(milliseconds: 3000),
  }) async {
    final results = <ProbeResult>[];
    for (final url in probeUrls) {
      results.add(await probe(url, timeout: timeout));
    }
    return results;
  }

  static Future<ProbeResult> probe(
    String url, {
    Duration timeout = const Duration(milliseconds: 3000),
  }) async {
    final uri = Uri.parse(url);
    final client = HttpClient()..connectionTimeout = timeout;
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(
            const Duration(milliseconds: 600),
            onTimeout: () {},
          );
      stopwatch.stop();
      return ProbeResult(
        uri: url,
        host: uri.host,
        statusCode: response.statusCode,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return ProbeResult(
        uri: url,
        host: uri.host,
        elapsedMs: stopwatch.elapsedMilliseconds,
        error: e.runtimeType.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 当前网络接口类型（Wi-Fi / 移动数据 / 无）
  static Future<String> interfaceSummary() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty) return '无接口';
      return results.map((r) => r.name).join(' + ');
    } catch (e) {
      return '读取失败 (${e.runtimeType})';
    }
  }
}
