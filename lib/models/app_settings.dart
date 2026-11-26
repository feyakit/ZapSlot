/// URL 匹配与生成策略
enum UrlRuleMode {
  /// 优先使用全局模板（支持支付宝直达 Scheme / 自定义 HTTPS 模板）
  globalTemplate,

  /// 优先使用该充电桩扫码记录的原始链接
  rawUrlFirst,
}

/// 预设跳转规则模板
class UrlRulePreset {
  const UrlRulePreset({
    required this.name,
    required this.description,
    required this.template,
    required this.recommendedMode,
  });

  final String name;
  final String description;
  final String template;
  final UrlRuleMode recommendedMode;
}

/// 应用全局规则与行为配置
class AppSettings {
  const AppSettings({
    this.ruleMode = UrlRuleMode.globalTemplate,
    this.globalUrlTemplate = defaultGlobalTemplate,
    this.serialRegex = defaultSerialRegex,
    this.quickInputPrefix = defaultQuickInputPrefix,
    int defaultPortCount = 10,
    this.autoLaunchInForeground = true,
  }) : defaultPortCount = defaultPortCount < 1
            ? 1
            : (defaultPortCount > 12 ? 12 : defaultPortCount);

  static const String defaultGlobalTemplate =
      'https://charge.example.com/start?sn={SN}&port={PORT}';
  static const String defaultSerialRegex = r'W\d{8}';
  static const String defaultQuickInputPrefix = 'W5200';

  static const List<UrlRulePreset> presets = [
    UrlRulePreset(
      name: '原始 HTTPS 链接模板',
      description: '替换桩号与端口参数后由系统/微信默认打开',
      template: 'https://charge.example.com/start?sn={SN}&port={PORT}',
      recommendedMode: UrlRuleMode.globalTemplate,
    ),
    UrlRulePreset(
      name: '支付宝小程序直达',
      description: '支持本地动态拼接 {SN} 与 {PORT}，免扫码跳过开屏广告',
      template:
          'alipays://platformapi/startapp?appId=2021000000000000&page=pages/charge/index&query=sn%3D{SN}%26port%3D{PORT}',
      recommendedMode: UrlRuleMode.globalTemplate,
    ),
    UrlRulePreset(
      name: '微信固定 Scheme 示例',
      description:
          '微信官方加密短链不支持本地拼接参数，建议填在单桩独立链接中（或使用已支持传参的外部 Scheme）',
      template: 'weixin://dl/business/?t=YOUR_TICKET',
      recommendedMode: UrlRuleMode.rawUrlFirst,
    ),
  ];

  final UrlRuleMode ruleMode;
  final String globalUrlTemplate;
  final String serialRegex;
  final String quickInputPrefix;
  final int defaultPortCount;
  final bool autoLaunchInForeground;

  AppSettings copyWith({
    UrlRuleMode? ruleMode,
    String? globalUrlTemplate,
    String? serialRegex,
    String? quickInputPrefix,
    int? defaultPortCount,
    bool? autoLaunchInForeground,
  }) {
    final nextPorts = defaultPortCount ?? this.defaultPortCount;
    return AppSettings(
      ruleMode: ruleMode ?? this.ruleMode,
      globalUrlTemplate: globalUrlTemplate ?? this.globalUrlTemplate,
      serialRegex: serialRegex ?? this.serialRegex,
      quickInputPrefix: quickInputPrefix ?? this.quickInputPrefix,
      defaultPortCount: nextPorts.clamp(1, 12),
      autoLaunchInForeground:
          autoLaunchInForeground ?? this.autoLaunchInForeground,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ruleMode': ruleMode.name,
      'globalUrlTemplate': globalUrlTemplate,
      'serialRegex': serialRegex,
      'quickInputPrefix': quickInputPrefix,
      'defaultPortCount': defaultPortCount,
      'autoLaunchInForeground': autoLaunchInForeground,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final modeName = json['ruleMode'] as String?;
    final parsedMode = UrlRuleMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => UrlRuleMode.globalTemplate,
    );
    final rawPorts = (json['defaultPortCount'] as num?)?.toInt() ?? 10;
    return AppSettings(
      ruleMode: parsedMode,
      globalUrlTemplate:
          (json['globalUrlTemplate'] as String?)?.trim().isNotEmpty == true
              ? (json['globalUrlTemplate'] as String).trim()
              : defaultGlobalTemplate,
      serialRegex: (json['serialRegex'] as String?)?.trim().isNotEmpty == true
          ? (json['serialRegex'] as String).trim()
          : defaultSerialRegex,
      quickInputPrefix:
          (json['quickInputPrefix'] as String?)?.trim().isNotEmpty == true
              ? (json['quickInputPrefix'] as String).trim().toUpperCase()
              : defaultQuickInputPrefix,
      defaultPortCount: rawPorts.clamp(1, 12),
      autoLaunchInForeground: json['autoLaunchInForeground'] as bool? ?? true,
    );
  }
}
