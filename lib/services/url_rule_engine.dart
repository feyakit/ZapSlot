import '../models/app_settings.dart';
import '../models/charging_station.dart';

/// 本地 URL 规则引擎：负责桩号正则提取、基础模板推导和三层优先级目标链接生成。
class UrlRuleEngine {
  const UrlRuleEngine._();

  /// 从扫码内容或 OCR 文本中提取桩号（默认匹配 `W\d{8}`），统一返回大写。
  static String? extractSerialNumber(
    String text, {
    String regexPattern = AppSettings.defaultSerialRegex,
  }) {
    if (text.trim().isEmpty) return null;

    final effectivePattern = regexPattern.trim().isEmpty
        ? AppSettings.defaultSerialRegex
        : regexPattern.trim();

    try {
      final regex = RegExp(effectivePattern, caseSensitive: false);
      final match = regex.firstMatch(text);
      return match?.group(0)?.toUpperCase();
    } on FormatException {
      final fallback =
          RegExp(AppSettings.defaultSerialRegex, caseSensitive: false);
      return fallback.firstMatch(text)?.group(0)?.toUpperCase();
    }
  }

  /// 将扫描到的原始 URL 中的桩号替换为 `{SN}` 占位符，便于复用为全局模板。
  static String extractBaseTemplateFromUrl(String rawUrl, String serialNumber) {
    final trimmedUrl = rawUrl.trim();
    final trimmedSn = serialNumber.trim();
    if (trimmedUrl.isEmpty || trimmedSn.isEmpty) {
      return trimmedUrl;
    }

    final snPattern = RegExp(RegExp.escape(trimmedSn), caseSensitive: false);
    if (!snPattern.hasMatch(trimmedUrl)) {
      return trimmedUrl;
    }
    return trimmedUrl.replaceAll(snPattern, '{SN}');
  }

  /// 根据三层优先级生成最终可跳转的 [Uri]：
  /// 1. 单桩自定义覆盖链接 (`customDeepLinkTemplate`)
  /// 2. 全局模板 (`globalUrlTemplate`，当策略为 `globalTemplate` 时)
  /// 3. 充电桩原始二维码链接 (`rawUrl`)
  static Uri? buildTargetUri(
    ChargingStation station,
    int port,
    AppSettings settings,
  ) {
    final safePort = port.clamp(1, 12);
    final customTemplate = station.customDeepLinkTemplate?.trim();

    if (customTemplate != null && customTemplate.isNotEmpty) {
      final resolvedCustom = _applyPlaceholders(
        customTemplate,
        station.serialNumber,
        safePort,
      );
      return _parseValidUri(resolvedCustom);
    }

    final globalTemplate = settings.globalUrlTemplate.trim();
    if (settings.ruleMode == UrlRuleMode.globalTemplate &&
        globalTemplate.isNotEmpty) {
      final resolvedGlobal = _applyPlaceholders(
        globalTemplate,
        station.serialNumber,
        safePort,
      );
      final globalUri = _parseValidUri(resolvedGlobal);
      if (globalUri != null) {
        return globalUri;
      }
    }

    final rawUrl = station.rawUrl.trim();
    if (rawUrl.isNotEmpty) {
      final resolvedRaw = _applyPlaceholders(
        rawUrl,
        station.serialNumber,
        safePort,
      );
      final rawUri = _parseValidUri(resolvedRaw);
      if (rawUri != null) {
        return rawUri;
      }
    }

    if (globalTemplate.isNotEmpty) {
      final fallbackResolved = _applyPlaceholders(
        globalTemplate,
        station.serialNumber,
        safePort,
      );
      return _parseValidUri(fallbackResolved);
    }

    return null;
  }

  /// 生成规则设置页中的实时预览字符串。
  static String previewUrl(
    String template, {
    String sampleSn = 'W52001715',
    int samplePort = 1,
  }) {
    if (template.trim().isEmpty) return '';
    return _applyPlaceholders(template.trim(), sampleSn, samplePort);
  }

  static String _applyPlaceholders(String template, String sn, int port) {
    return template
        .replaceAll('{SN}', Uri.encodeComponent(sn.trim().toUpperCase()))
        .replaceAll('{sn}', Uri.encodeComponent(sn.trim().toUpperCase()))
        .replaceAll('{PORT}', port.toString())
        .replaceAll('{port}', port.toString());
  }

  static Uri? _parseValidUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || uri.scheme.isEmpty) {
      return null;
    }
    return uri;
  }
}
