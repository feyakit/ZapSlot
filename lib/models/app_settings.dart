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
    this.autoAddScannedStation = true,
    int portIndexBase = 0,
  })  : defaultPortCount = defaultPortCount < 1
            ? 1
            : (defaultPortCount > 12 ? 12 : defaultPortCount),
        portIndexBase = portIndexBase == 1 ? 1 : 0;

  /// 默认在线直达：保留原二维码全部参数，并附上选中的插座号（gun_num）直达支付页。
  static const String defaultGlobalTemplate =
      'alipays://platformapi/startapp?appId=20000067&url={RAW_URL_PORT0_ENCODED}';
  static const String defaultFallbackRawUrlTemplate =
      'http://weixin.weiyunchong.com/payQRcode.html?device_no={SN}';
  static const String defaultSerialRegex = r'W\d{8}';
  static const String defaultQuickInputPrefix = 'W5200';

  static const List<UrlRulePreset> presets = [
    UrlRulePreset(
      name: '微云充 · 在线选号直达支付（默认）',
      description: '保留原二维码全部参数（含签名/门店参数）并附加 gun_num，选几号口就直达几号口的支付页',
      template:
          'alipays://platformapi/startapp?appId=20000067&url={RAW_URL_PORT0_ENCODED}',
      recommendedMode: UrlRuleMode.globalTemplate,
    ),
    UrlRulePreset(
      name: '通用原始码 · 支付宝直达（进选口页）',
      description: '完整保留原二维码所有参数并交由支付宝内置浏览器打开，进入选口页自行选择空闲插座',
      template:
          'alipays://platformapi/startapp?appId=20000067&url={RAW_URL_ENCODED}',
      recommendedMode: UrlRuleMode.globalTemplate,
    ),
    UrlRulePreset(
      name: '微云充 · 按桩号拼接支付宝直达',
      description: '仅按 {SN} 拼接微云充地址（适合无签名参数的纯编号桩或 OCR / 尾号直达）',
      template:
          'alipays://platformapi/startapp?appId=20000067&url=http%3A%2F%2Fweixin.weiyunchong.com%2FpayQRcode.html%3Fdevice_no%3D{SN}',
      recommendedMode: UrlRuleMode.globalTemplate,
    ),
    UrlRulePreset(
      name: '微云充 · 原始 H5 链接',
      description: '直接拼接微云充原始网页地址并交由系统默认打开',
      template: 'http://weixin.weiyunchong.com/payQRcode.html?device_no={SN}',
      recommendedMode: UrlRuleMode.globalTemplate,
    ),
    UrlRulePreset(
      name: '支付宝小程序直达模板',
      description: '适合已知小程序 appId 与页面路径的充电品牌，支持动态拼接 {SN} 与 {PORT}',
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

  /// 扫到未收录的新二维码时是否自动建桩（不再弹确认浮层）。
  final bool autoAddScannedStation;

  /// 插座号传参基准：0 = gun_num 从 0 开始（1号口传 0），1 = 与服务端 1 起始一致。
  final int portIndexBase;

  AppSettings copyWith({
    UrlRuleMode? ruleMode,
    String? globalUrlTemplate,
    String? serialRegex,
    String? quickInputPrefix,
    int? defaultPortCount,
    bool? autoLaunchInForeground,
    bool? autoAddScannedStation,
    int? portIndexBase,
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
      autoAddScannedStation:
          autoAddScannedStation ?? this.autoAddScannedStation,
      portIndexBase: portIndexBase ?? this.portIndexBase,
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
      'autoAddScannedStation': autoAddScannedStation,
      'portIndexBase': portIndexBase,
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
      autoAddScannedStation: json['autoAddScannedStation'] as bool? ?? true,
      portIndexBase: (json['portIndexBase'] as num?)?.toInt() ?? 0,
    );
  }
}
