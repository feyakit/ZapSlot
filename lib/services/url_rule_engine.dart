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

  /// 将包含 `{SN}` 的基础 HTTP/HTTPS 模板封装为支付宝内置浏览器直达模板。
  static String buildAlipayH5Template(String baseTemplate) {
    final trimmed = baseTemplate.trim();
    if (trimmed.isEmpty) return '';
    // 先把 {SN}/{PORT}/{PORT_0} 临时替换为占位标记，避免被 Uri.encodeComponent 转义。
    const snToken = '__CHARGE_QUICK_SN__';
    const portToken = '__CHARGE_QUICK_PORT__';
    const port0Token = '__CHARGE_QUICK_PORT0__';
    final masked = trimmed
        .replaceAll('{SN}', snToken)
        .replaceAll('{sn}', snToken)
        .replaceAll('{PORT_0}', port0Token)
        .replaceAll('{port_0}', port0Token)
        .replaceAll('{PORT}', portToken)
        .replaceAll('{port}', portToken);
    final encoded = Uri.encodeComponent(masked)
        .replaceAll(snToken, '{SN}')
        .replaceAll(port0Token, '{PORT_0}')
        .replaceAll(portToken, '{PORT}');
    return 'alipays://platformapi/startapp?appId=20000067&url=$encoded';
  }

  /// 校验正则表达式是否合法，返回错误信息或 null。
  static String? validateRegex(String pattern) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) return null;
    try {
      RegExp(trimmed);
      return null;
    } on FormatException catch (e) {
      return '正则语法错误：${e.message}';
    }
  }

  /// 校验模板在代入示例参数后是否为合法带 Scheme 的 URI。
  static String? validateTemplate(String template) {
    final trimmed = template.trim();
    if (trimmed.isEmpty) return '模板不能为空';
    final sample = previewUrl(trimmed);
    final uri = _parseValidUri(sample);
    if (uri == null) {
      return '链接缺少有效协议头（如 alipays://、weixin://、https://、http://）';
    }
    return null;
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
    final rawUrl = station.rawUrl.trim();

    if (customTemplate != null && customTemplate.isNotEmpty) {
      final resolvedCustom = _applyPlaceholders(
        customTemplate,
        station.serialNumber,
        safePort,
        rawUrl: rawUrl,
      );
      final customUri = _parseValidUri(resolvedCustom);
      if (customUri != null) {
        return customUri;
      }
    }

    final globalTemplate = settings.globalUrlTemplate.trim();
    if (settings.ruleMode == UrlRuleMode.globalTemplate &&
        globalTemplate.isNotEmpty) {
      final resolvedGlobal = _applyPlaceholders(
        globalTemplate,
        station.serialNumber,
        safePort,
        rawUrl: rawUrl,
      );
      if (resolvedGlobal != null) {
        final globalUri = _parseValidUri(resolvedGlobal);
        if (globalUri != null) {
          return globalUri;
        }
      }
    }

    if (rawUrl.isNotEmpty) {
      final resolvedRaw = _applyPlaceholders(
        rawUrl,
        station.serialNumber,
        safePort,
        rawUrl: rawUrl,
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
        rawUrl: rawUrl,
      );
      return _parseValidUri(fallbackResolved);
    }

    return null;
  }

  /// 判断当前生效的链接规则是否会把用户选中的插座号传入目标链接。
  static bool templateUsesPort(ChargingStation station, AppSettings settings) {
    final custom = station.customDeepLinkTemplate?.trim();
    final String effectiveTemplate;
    if (custom != null && custom.isNotEmpty) {
      effectiveTemplate = custom;
    } else if (settings.ruleMode == UrlRuleMode.globalTemplate &&
        settings.globalUrlTemplate.trim().isNotEmpty) {
      effectiveTemplate = settings.globalUrlTemplate.trim();
    } else {
      effectiveTemplate = station.rawUrl.trim();
    }
    final lower = effectiveTemplate.toLowerCase();
    return lower.contains('{port}') ||
        lower.contains('{port_0}') ||
        lower.contains('{raw_url_port0_encoded}');
  }

  /// 生成规则设置页中的实时预览字符串。
  static String previewUrl(
    String template, {
    String sampleSn = 'W52001715',
    int samplePort = 1,
    String? sampleRawUrl,
  }) {
    if (template.trim().isEmpty) return '';
    final effectiveRaw = sampleRawUrl ??
        'http://weixin.weiyunchong.com/payQRcode.html?device_no=${sampleSn.trim().toUpperCase()}';
    return _applyPlaceholders(
          template.trim(),
          sampleSn,
          samplePort,
          rawUrl: effectiveRaw,
        ) ??
        '';
  }

  static String? _applyPlaceholders(
    String template,
    String sn,
    int port, {
    String rawUrl = '',
  }) {
    final lower = template.toLowerCase();
    final usesRawUrl = lower.contains('{raw_url}') ||
        lower.contains('{raw_url_encoded}') ||
        lower.contains('{raw_url_port0_encoded}');
    final trimmedRaw = rawUrl.trim();
    if (usesRawUrl && trimmedRaw.isEmpty) {
      return null;
    }

    final encodedSn = Uri.encodeComponent(sn.trim().toUpperCase());
    final encodedRaw = Uri.encodeComponent(trimmedRaw);
    final zeroBasedPort = (port - 1).clamp(0, 11).toString();

    String encodedRawWithPort0 = '';
    if (lower.contains('{raw_url_port0_encoded}') && trimmedRaw.isNotEmpty) {
      final parsedRaw = Uri.tryParse(trimmedRaw);
      if (parsedRaw != null && parsedRaw.hasScheme) {
        final mergedParams = Map<String, String>.from(parsedRaw.queryParameters)
          ..['gun_num'] = zeroBasedPort;
        encodedRawWithPort0 = Uri.encodeComponent(
          parsedRaw.replace(queryParameters: mergedParams).toString(),
        );
      } else {
        encodedRawWithPort0 = encodedRaw;
      }
    }

    return template
        .replaceAll('{SN}', encodedSn)
        .replaceAll('{sn}', encodedSn)
        .replaceAll('{PORT_0}', zeroBasedPort)
        .replaceAll('{port_0}', zeroBasedPort)
        .replaceAll('{PORT}', port.toString())
        .replaceAll('{port}', port.toString())
        .replaceAll('{RAW_URL_PORT0_ENCODED}', encodedRawWithPort0)
        .replaceAll('{raw_url_port0_encoded}', encodedRawWithPort0)
        .replaceAll('{RAW_URL_ENCODED}', encodedRaw)
        .replaceAll('{raw_url_encoded}', encodedRaw)
        .replaceAll('{RAW_URL}', trimmedRaw)
        .replaceAll('{raw_url}', trimmedRaw);
  }

  static Uri? _parseValidUri(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme || uri.scheme.isEmpty) {
      return null;
    }
    return uri;
  }
}
