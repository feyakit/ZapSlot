/// 外观主题模式（5 浅透液态玻璃 / 6 深透黑曜玻璃 / 跟随系统）
enum AppThemePreference {
  system,
  light,
  dark,
}

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
    this.themePreference = AppThemePreference.system,
    this.commonChargeAmounts = defaultCommonAmounts,
  })  : defaultPortCount = defaultPortCount < 1
            ? 1
            : (defaultPortCount > 12 ? 12 : defaultPortCount),
        portIndexBase = portIndexBase == 1 ? 1 : 0;

  static const List<double> defaultCommonAmounts = [1.0, 1.5, 2.0, 3.0];

  /// 默认在线直达：直达莱充小程序 commodity 选套餐付款页，0–9 插座号一一对应传入 gun_num。
  static const String defaultGlobalTemplate =
      'alipays://platformapi/startapp?appId=2019012363098597&page=pagesEbike%2Fcommodity%2Fcommodity%3Fdevice_no%3D{SN}%26gun_num%3D{PORT_0}%26from%3DebikePile';
  static const String defaultFallbackRawUrlTemplate =
      'http://weixin.weiyunchong.com/payQRcode.html?device_no={SN}';
  static const String defaultSerialRegex = r'W\d{8}';
  static const String defaultQuickInputPrefix = 'W5200';

  static const List<UrlRulePreset> presets = [
    UrlRulePreset(
      name: '莱充小程序 · 按插口直达选套餐付款页（默认）',
      description: '直达莱充 commodity 付款页，0–9 插座号一一对应传入 gun_num，跳过扫码与选插座页',
      template:
          'alipays://platformapi/startapp?appId=2019012363098597&page=pagesEbike%2Fcommodity%2Fcommodity%3Fdevice_no%3D{SN}%26gun_num%3D{PORT_0}%26from%3DebikePile',
      recommendedMode: UrlRuleMode.globalTemplate,
    ),
    UrlRulePreset(
      name: '莱充小程序 · 直达选插座页（查看空闲口）',
      description: '直达莱充 ebikePile 选插座页（appId=2019012363098597），先看各口实时空闲状态再选口',
      template:
          'alipays://platformapi/startapp?appId=2019012363098597&page=pagesEbike%2FebikePile%2FebikePile%3Fdevice_no%3D{SN}',
      recommendedMode: UrlRuleMode.globalTemplate,
    ),
    UrlRulePreset(
      name: '支付宝原生扫码路由直达（通用全部品牌）',
      description: '完整保留原二维码所有参数并走支付宝原生扫码路由（自动进品牌小程序），适合非莱充品牌',
      template:
          'alipays://platformapi/startapp?saId=10000007&qrcode={RAW_URL_ENCODED}',
      recommendedMode: UrlRuleMode.globalTemplate,
    ),
    UrlRulePreset(
      name: '微云充 H5 · 在线选号直达支付（旧版兼容）',
      description: '强制用支付宝 H5 浏览器打开微云充旧版网页并附加 gun_num',
      template:
          'alipays://platformapi/startapp?appId=20000067&url={RAW_URL_PORT0_ENCODED}',
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

  /// 外观主题偏好：跟随系统 / 浅透液态玻璃 / 深透黑曜玻璃
  final AppThemePreference themePreference;

  /// 自定义常用充电金额列表（元），用于足迹页一键记账
  final List<double> commonChargeAmounts;

  /// 展示给用户的插座编号（与微云充页面一致：0 起始时端口 1 显示为 0）。
  int socketNumber(int port) => (port - 1 + portIndexBase).clamp(0, 99);

  AppSettings copyWith({
    UrlRuleMode? ruleMode,
    String? globalUrlTemplate,
    String? serialRegex,
    String? quickInputPrefix,
    int? defaultPortCount,
    bool? autoLaunchInForeground,
    bool? autoAddScannedStation,
    int? portIndexBase,
    AppThemePreference? themePreference,
    List<double>? commonChargeAmounts,
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
      themePreference: themePreference ?? this.themePreference,
      commonChargeAmounts: commonChargeAmounts ?? this.commonChargeAmounts,
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
      'themePreference': themePreference.name,
      'commonChargeAmounts': commonChargeAmounts,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final modeName = json['ruleMode'] as String?;
    final parsedMode = UrlRuleMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => UrlRuleMode.globalTemplate,
    );
    final themeName = json['themePreference'] as String?;
    final parsedTheme = AppThemePreference.values.firstWhere(
      (t) => t.name == themeName,
      orElse: () => AppThemePreference.system,
    );
    final rawAmounts = json['commonChargeAmounts'] as List<dynamic>?;
    final parsedAmounts = rawAmounts
        ?.whereType<num>()
        .map((n) => double.parse(n.toDouble().toStringAsFixed(2)))
        .where((n) => n > 0 && n <= 999)
        .toSet()
        .toList();
    if (parsedAmounts != null) {
      parsedAmounts.sort();
    }
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
      themePreference: parsedTheme,
      commonChargeAmounts: (parsedAmounts != null && parsedAmounts.isNotEmpty)
          ? parsedAmounts
          : defaultCommonAmounts,
    );
  }
}
