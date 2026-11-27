import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';
import '../providers/app_providers.dart';
import '../services/ad_skip_service.dart';
import '../services/url_rule_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/network_diagnostics_sheet.dart';

/// URL 重写规则与全局参数设置页
class RuleSettingsScreen extends ConsumerStatefulWidget {
  const RuleSettingsScreen({super.key});

  @override
  ConsumerState<RuleSettingsScreen> createState() => _RuleSettingsScreenState();
}

class _RuleSettingsScreenState extends ConsumerState<RuleSettingsScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _templateController;
  late final TextEditingController _regexController;
  late final TextEditingController _prefixController;
  late UrlRuleMode _ruleMode;
  late int _defaultPortCount;
  late bool _autoLaunchInForeground;
  late bool _autoAddScannedStation;
  late bool _portIndexBaseZero;
  bool _adSkipEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = ref.read(settingsProvider);
    _templateController =
        TextEditingController(text: settings.globalUrlTemplate);
    _regexController = TextEditingController(text: settings.serialRegex);
    _prefixController = TextEditingController(text: settings.quickInputPrefix);
    _ruleMode = settings.ruleMode;
    _defaultPortCount = settings.defaultPortCount;
    _autoLaunchInForeground = settings.autoLaunchInForeground;
    _autoAddScannedStation = settings.autoAddScannedStation;
    _portIndexBaseZero = settings.portIndexBase == 0;
    _refreshAdSkipStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAdSkipStatus();
    }
  }

  Future<void> _refreshAdSkipStatus() async {
    if (!AdSkipService.isSupported) return;
    final enabled = await AdSkipService.isEnabled();
    if (mounted) {
      setState(() => _adSkipEnabled = enabled);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _templateController.dispose();
    _regexController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  void _insertPlaceholder(String token) {
    final text = _templateController.text;
    final selection = _templateController.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final nextText = text.replaceRange(start, end, token);
    _templateController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() {});
  }

  Future<void> _testPreviewUrl(String preview) async {
    final uri = Uri.tryParse(preview.trim());
    if (uri == null || !uri.hasScheme) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前预览链接无效，无法测试跳转')),
      );
      return;
    }
    if (uri.scheme.toLowerCase() == 'alipays') {
      await AdSkipService.armForAlipayLaunch();
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('未能唤起 ${uri.scheme} 应用，请确认手机已安装对应 App'),
        ),
      );
    }
  }

  Future<void> _save() async {
    final templateText = _templateController.text.trim().isEmpty
        ? AppSettings.defaultGlobalTemplate
        : _templateController.text.trim();
    final regexText = _regexController.text.trim().isEmpty
        ? AppSettings.defaultSerialRegex
        : _regexController.text.trim();

    final templateError = UrlRuleEngine.validateTemplate(templateText);
    if (templateError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(templateError)),
      );
      return;
    }
    final regexError = UrlRuleEngine.validateRegex(regexText);
    if (regexError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(regexError)),
      );
      return;
    }

    final next = AppSettings(
      ruleMode: _ruleMode,
      globalUrlTemplate: templateText,
      serialRegex: regexText,
      quickInputPrefix: _prefixController.text.trim().isEmpty
          ? AppSettings.defaultQuickInputPrefix
          : _prefixController.text.trim().toUpperCase(),
      defaultPortCount: _defaultPortCount,
      autoLaunchInForeground: _autoLaunchInForeground,
      autoAddScannedStation: _autoAddScannedStation,
      portIndexBase: _portIndexBaseZero ? 0 : 1,
    );
    await ref.read(settingsProvider.notifier).updateSettings(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('规则配置已保存')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final samplePrefix = _prefixController.text.trim().isEmpty
        ? AppSettings.defaultQuickInputPrefix
        : _prefixController.text.trim().toUpperCase();
    final preview = UrlRuleEngine.previewUrl(
      _templateController.text,
      sampleSn: '${samplePrefix}1715',
      samplePort: 3,
      portIndexBase: _portIndexBaseZero ? 0 : 1,
    );
    final templateError = _templateController.text.trim().isEmpty
        ? null
        : UrlRuleEngine.validateTemplate(_templateController.text);
    final regexError = UrlRuleEngine.validateRegex(_regexController.text);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '规则与直达设置',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              '保存',
              style: TextStyle(
                color: AppColors.emerald,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        children: [
          _SectionCard(
            title: '1. 链接匹配优先级',
            subtitle: '若单桩设置了独立覆盖链接，则始终最高优使用该单桩链接。',
            child: SegmentedButton<UrlRuleMode>(
              segments: const [
                ButtonSegment(
                  value: UrlRuleMode.globalTemplate,
                  label: Text('全局模板优先'),
                  icon: Icon(Icons.auto_fix_high_rounded, size: 18),
                ),
                ButtonSegment(
                  value: UrlRuleMode.rawUrlFirst,
                  label: Text('原始扫码链接优先'),
                  icon: Icon(Icons.qr_code_2_rounded, size: 18),
                ),
              ],
              selected: {_ruleMode},
              onSelectionChanged: (values) {
                setState(() => _ruleMode = values.first);
              },
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: '2. 全局 URL / Deep Link 模板',
            subtitle:
                '支持 {SN}（桩号）、{PORT}（插座口）与 {RAW_URL_ENCODED}（编码后原始码链接），跳过开屏广告直达小程序或支付宝。',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _templateController,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: '输入 alipays:// / weixin:// / https:// 模板',
                    errorText: templateError,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('插入 {SN}'),
                      backgroundColor: AppColors.surfaceElevated,
                      side: const BorderSide(color: AppColors.cyan),
                      onPressed: () => _insertPlaceholder('{SN}'),
                    ),
                    ActionChip(
                      label: const Text('插入 {PORT}'),
                      backgroundColor: AppColors.surfaceElevated,
                      side: const BorderSide(color: AppColors.cyan),
                      onPressed: () => _insertPlaceholder('{PORT}'),
                    ),
                    ActionChip(
                      label: const Text('插入 {PORT_0}'),
                      backgroundColor: AppColors.surfaceElevated,
                      side: const BorderSide(color: AppColors.cyan),
                      onPressed: () => _insertPlaceholder('{PORT_0}'),
                    ),
                    ActionChip(
                      label: const Text('插入 {RAW_URL_ENCODED}'),
                      backgroundColor: AppColors.surfaceElevated,
                      side: const BorderSide(color: AppColors.cyan),
                      onPressed: () => _insertPlaceholder('{RAW_URL_ENCODED}'),
                    ),
                    ActionChip(
                      label: const Text('插入 {RAW_URL_PORT0_ENCODED}'),
                      backgroundColor: AppColors.surfaceElevated,
                      side: const BorderSide(color: AppColors.cyan),
                      onPressed: () =>
                          _insertPlaceholder('{RAW_URL_PORT0_ENCODED}'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '实时渲染预览（示例 3号口）',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          if (preview.isNotEmpty && templateError == null)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _testPreviewUrl(preview),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Text(
                                  '测试跳转 ↗',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.cyan,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preview.isEmpty ? '（模板为空）' : preview,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: AppColors.emerald,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: '3. 常用 Scheme 预设（点击填入）',
            subtitle: '提示：支付宝支持本地动态拼接参数；微信官方加密短链通常无参数位，建议写在单桩“独立覆盖链接”中。',
            child: Column(
              children: AppSettings.presets.map((preset) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        _templateController.text = preset.template;
                        _ruleMode = preset.recommendedMode;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  preset.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              const Text(
                                '应用',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.cyan,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            preset.description,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: '4. 识别与快捷操作参数',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _regexController,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: '桩号提取正则',
                    hintText: r'W\d{8}',
                    errorText: regexError,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _prefixController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: '尾号直达默认前缀',
                    hintText: 'W5200',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '每台桩插座口数量',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      '$_defaultPortCount 个',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.cyan,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _defaultPortCount.toDouble(),
                  min: 4,
                  max: 12,
                  divisions: 8,
                  activeColor: AppColors.cyan,
                  onChanged: (value) {
                    setState(() => _defaultPortCount = value.round());
                  },
                ),
                SwitchListTile(
                  value: _autoLaunchInForeground,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.emerald,
                  title: const Text('前台恢复信号时自动跳转'),
                  subtitle: const Text(
                    '亮屏拿着手机出电梯时自动拉起目标 App；锁屏/后台则推送高优先级通知点击直达',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  onChanged: (value) {
                    setState(() => _autoLaunchInForeground = value);
                  },
                ),
                SwitchListTile(
                  value: _autoAddScannedStation,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.emerald,
                  title: const Text('扫到新码自动添加充电桩'),
                  subtitle: const Text(
                    '扫码或 OCR 识别到未收录的桩号时自动建桩并置顶；已收录的桩只更新二维码，保留别名与自定义链接',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  onChanged: (value) {
                    setState(() => _autoAddScannedStation = value);
                  },
                ),
                SwitchListTile(
                  value: _portIndexBaseZero,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.emerald,
                  title: const Text('插座号按 0 起始传参'),
                  subtitle: const Text(
                    '1 号插座传 gun_num=0（微云充默认如此）；若目标页高亮的插座号与所选不一致，关掉此项改为 1 起始',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  onChanged: (value) {
                    setState(() => _portIndexBaseZero = value);
                  },
                ),
                if (AdSkipService.isSupported) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _adSkipEnabled
                            ? AppColors.emerald.withValues(alpha: 0.7)
                            : AppColors.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _adSkipEnabled
                                  ? Icons.bolt_rounded
                                  : Icons.fast_forward_rounded,
                              size: 18,
                              color: _adSkipEnabled
                                  ? AppColors.emerald
                                  : AppColors.amber,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '自动跳过支付宝开屏广告',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: (_adSkipEnabled
                                        ? AppColors.emerald
                                        : AppColors.amber)
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _adSkipEnabled ? '已开启' : '未开启',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _adSkipEnabled
                                      ? AppColors.emerald
                                      : AppColors.amber,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '仅在从「闪雀」直达支付宝后的 6 秒内自动点击开屏「跳过」按钮，超时即休眠，平时零耗电。',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 42,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: _adSkipEnabled
                                    ? AppColors.border
                                    : AppColors.emerald,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () async {
                              await AdSkipService.openAccessibilitySettings();
                            },
                            icon: Icon(
                              Icons.accessibility_new_rounded,
                              size: 18,
                              color: _adSkipEnabled
                                  ? AppColors.textSecondary
                                  : AppColors.emerald,
                            ),
                            label: Text(
                              _adSkipEnabled
                                  ? '前往无障碍设置管理'
                                  : '前往无障碍开启「闪雀 · 跳过支付宝开屏广告」',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _adSkipEnabled
                                    ? AppColors.textSecondary
                                    : AppColors.emerald,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => showNetworkDiagnosticsSheet(context),
                  icon: const Icon(
                    Icons.wifi_tethering_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  label: const Text(
                    '网络诊断（排查"有信号却提示离线"）',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    '构建版本：${const String.fromEnvironment('APP_BUILD', defaultValue: 'dev')}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
