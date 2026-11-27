import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/charging_station.dart';
import '../providers/app_providers.dart';
import '../providers/charging_reminder_provider.dart';
import '../providers/station_live_provider.dart';
import '../services/station_lookup_service.dart';
import '../services/url_rule_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/network_diagnostics_sheet.dart';
import '../widgets/quick_serial_modal.dart';
import '../widgets/station_card.dart';
import 'footprint_tab.dart';
import 'offline_scanner_screen.dart';
import 'rule_settings_screen.dart';

/// 主面板：全透明液态玻璃 + 底部三栏悬浮导航（充电 / 足迹 / 设置）。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  String? _expandedStationId;
  bool _didInitExpanded = false;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);

    ref.listen<String?>(
      launchQueueProvider.select((s) => s.statusMessage),
      (prev, msg) {
        if (msg != null && msg != prev) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(msg)));
        }
      },
    );

    final hasReminder =
        ref.watch(chargingReminderProvider.select((r) => r != null));
    final hasPendingTask =
        ref.watch(launchQueueProvider.select((s) => s.hasPendingTask));

    return ZapAuroraBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildChargeTab(context),
            FootprintTab(
              onOpenMiniProgram: () => _openLaiChongMiniProgram(context),
            ),
            const RuleSettingsScreen(embedded: true),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: ZapGlassCard(
              borderRadius: 28,
              blurSigma: 28,
              borderColor: p.navBorder,
              backgroundColors: [p.navGlass, p.navGlass],
              child: NavigationBar(
                height: 62,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                shadowColor: Colors.transparent,
                indicatorColor: p.primary.withValues(alpha: 0.16),
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) {
                  HapticFeedback.selectionClick();
                  setState(() => _currentIndex = index);
                },
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: hasPendingTask,
                      backgroundColor: p.offline,
                      smallSize: 7,
                      child: Icon(
                        Icons.electric_moped_rounded,
                        color: p.textSecondary,
                      ),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: hasPendingTask,
                      backgroundColor: p.offline,
                      smallSize: 7,
                      child: Icon(
                        Icons.electric_moped_rounded,
                        color: p.primary,
                      ),
                    ),
                    label: '充电',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: hasReminder,
                      backgroundColor: p.primary,
                      smallSize: 7,
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: p.textSecondary,
                      ),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: hasReminder,
                      backgroundColor: p.primary,
                      smallSize: 7,
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: p.primary,
                      ),
                    ),
                    label: '足迹',
                  ),
                  NavigationDestination(
                    icon: Icon(
                      Icons.tune_rounded,
                      color: p.textSecondary,
                    ),
                    selectedIcon: Icon(
                      Icons.tune_rounded,
                      color: p.primary,
                    ),
                    label: '设置',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChargeTab(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final stations = ref.watch(stationsProvider);
    final settings = ref.watch(settingsProvider);
    final isOnline = ref.watch(launchQueueProvider.select((s) => s.isOnline));
    final hasPendingTask =
        ref.watch(launchQueueProvider.select((s) => s.hasPendingTask));
    final pendingStationId =
        ref.watch(launchQueueProvider.select((s) => s.pendingStation?.id));
    final pendingPort =
        ref.watch(launchQueueProvider.select((s) => s.pendingPort));
    final reminder = ref.watch(chargingReminderProvider);

    if (stations.isNotEmpty) {
      if (!_didInitExpanded) {
        _expandedStationId = stations.first.id;
        _didInitExpanded = true;
      } else if (_expandedStationId != null &&
          stations.every((s) => s.id != _expandedStationId)) {
        _expandedStationId = stations.first.id;
      }
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildTopHeader(context),
          _buildQuickActionStrip(context),
          if (hasPendingTask) _buildActiveQueueBanner(context),
          if (reminder != null) _buildReminderBanner(context, reminder),
          Expanded(
            child: stations.isEmpty
                ? _buildEmptyState(context)
                : RefreshIndicator(
                    color: p.primary,
                    backgroundColor: p.modalSurface,
                    onRefresh: () async {
                      await ref
                          .read(launchQueueProvider.notifier)
                          .refreshNetworkStatus();
                      await ref
                          .read(stationLiveProvider.notifier)
                          .refreshAll();
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: stations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final station = stations[index];
                        final isQueuedHere = pendingStationId == station.id;
                        final liveInfo = ref.watch(
                          stationLiveProvider
                              .select((s) => s.byStationId[station.id]),
                        );
                        final isRefreshing = ref.watch(
                          stationLiveProvider.select(
                            (s) => s.refreshingIds.contains(station.id),
                          ),
                        );
                        final completedPortLabel = ref.watch(
                          recentlyCompletedStationsProvider
                              .select((m) => m[station.id]),
                        );
                        return StationCard(
                          key: ValueKey(station.id),
                          station: station,
                          portCount:
                              station.portCount ?? settings.defaultPortCount,
                          isOnline: isOnline,
                          isQueuedHere: isQueuedHere,
                          queuedPort: isQueuedHere ? pendingPort : null,
                          usesPort: UrlRuleEngine.templateUsesPort(
                            station,
                            settings,
                          ),
                          portIndexBase: settings.portIndexBase,
                          liveInfo: liveInfo,
                          isRefreshing: isRefreshing,
                          isFirst: index == 0,
                          isExpanded: station.id == _expandedStationId,
                          watchingPortLabel:
                              reminder?.watchStationId == station.id
                                  ? reminder!.portLabel
                                  : null,
                          completedPortLabel: completedPortLabel,
                          onDismissCompleted: () {
                            final next = Map<String, String>.from(
                              ref.read(recentlyCompletedStationsProvider),
                            )..remove(station.id);
                            ref
                                .read(recentlyCompletedStationsProvider.notifier)
                                .state = next;
                          },
                          onToggleExpand: () {
                            setState(() {
                              _expandedStationId =
                                  _expandedStationId == station.id
                                      ? null
                                      : station.id;
                            });
                          },
                          onRefreshLive: () => ref
                              .read(stationLiveProvider.notifier)
                              .refreshStation(station.id),
                          onPinToTop: () {
                            setState(() => _expandedStationId = station.id);
                            ref
                                .read(stationsProvider.notifier)
                                .pinStationToTop(station.id);
                          },
                          onScheduleReminder: (port) => _showReminderPicker(
                            context,
                            station,
                            port,
                            station.socketLabel(port, settings.portIndexBase),
                          ),
                          onOpenMiniProgram: () =>
                              _openLaiChongMiniProgram(context),
                          onTrigger: (port) async {
                            await ref
                                .read(launchQueueProvider.notifier)
                                .triggerOrQueue(station, port);
                          },
                          onCopyLink: (port) async {
                            final uri = UrlRuleEngine.buildTargetUri(
                              station,
                              port,
                              settings,
                            );
                            if (uri == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('无法生成有效链接，请检查规则设置'),
                                ),
                              );
                              return;
                            }
                            await Clipboard.setData(
                              ClipboardData(text: uri.toString()),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '已复制 ${station.serialNumber} (${settings.socketNumber(port)}号口) 目标链接',
                                  ),
                                ),
                              );
                          },
                          onEdit: () => _showStationEditor(
                            context,
                            existing: station,
                          ),
                          onRename: () => _showQuickRenameDialog(
                            context,
                            station,
                          ),
                          onDelete: () => _confirmDelete(
                            context,
                            station,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionStrip(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _QuickActionChip(
              icon: Icons.qr_code_scanner_rounded,
              label: '离线扫新桩',
              color: p.primaryFill,
              textColor: p.onPrimary,
              filled: true,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const OfflineScannerScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickActionChip(
              icon: Icons.dialpad_rounded,
              label: '输编号直达',
              color: p.primary,
              textColor: p.textPrimary,
              onTap: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const QuickSerialModal(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeader(
    BuildContext context,
  ) {
    final p = AppTheme.paletteOf(context);
    final isOnline = ref.watch(launchQueueProvider.select((s) => s.isOnline));
    final isChecking =
        ref.watch(launchQueueProvider.select((s) => s.isChecking));
    final badgeColor = isOnline ? p.idle : p.offline;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.asset(
              'assets/images/logo.png',
              width: 38,
              height: 38,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '闪雀',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: p.textPrimary,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  isOnline ? '闪雀就绪 · 点桩展开选口' : '地库无网 · 选好插口先排队',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: p.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(launchQueueProvider.notifier).refreshNetworkStatus();
            },
            onLongPress: () => _showNetworkDiagnostics(context),
            child: ZapGlassCard(
              borderRadius: 24,
              blurSigma: 16,
              borderColor: p.secondaryBorder,
              backgroundColors: [p.secondaryBg, p.secondaryBg],
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: badgeColor.withValues(alpha: 0.45),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isChecking
                        ? '检测中...'
                        : (isOnline ? '网络就绪' : '地库离线'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: p.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showStationEditor(context),
            child: ZapGlassCard(
              borderRadius: 18,
              blurSigma: 16,
              borderColor: p.secondaryBorder,
              backgroundColors: [p.secondaryBg, p.secondaryBg],
              child: SizedBox(
                width: 34,
                height: 34,
                child: Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: p.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 长按网络胶囊：现场排查"有信号却提示离线"。
  Future<void> _showNetworkDiagnostics(BuildContext context) async {
    await showNetworkDiagnosticsSheet(context);
  }

  Widget _buildActiveQueueBanner(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final station =
        ref.watch(launchQueueProvider.select((s) => s.pendingStation));
    final port = ref.watch(launchQueueProvider.select((s) => s.pendingPort));
    final queuedAt = ref.watch(launchQueueProvider.select((s) => s.queuedAt));
    final isOnline = ref.watch(launchQueueProvider.select((s) => s.isOnline));
    final settings = ref.watch(settingsProvider);
    if (station == null || port == null) return const SizedBox.shrink();

    final displayPort = settings.socketNumber(port);
    final accent = isOnline ? p.idle : p.offline;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ZapGlassCard(
        borderRadius: 18,
        borderColor: accent.withValues(alpha: 0.7),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              isOnline
                  ? Icons.notifications_active_rounded
                  : Icons.wifi_off_rounded,
              color: accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOnline
                        ? '信号已恢复 · 准备直达 ${station.serialNumber}'
                        : '离线排队中 · 出电梯有网自动唤起',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${station.alias} · $displayPort号插座${_formatQueuedElapsed(queuedAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: p.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (isOnline)
              TextButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.read(launchQueueProvider.notifier).retryPendingNow();
                },
                child: Text(
                  '立即唤醒',
                  style: TextStyle(
                    color: p.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(launchQueueProvider.notifier).cancelQueue();
              },
              child: Text(
                '取消排队',
                style: TextStyle(
                  color: p.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatQueuedElapsed(DateTime? queuedAt) {
    if (queuedAt == null) return '';
    final diff = DateTime.now().difference(queuedAt);
    if (diff.inSeconds < 60) return ' · 刚刚排队';
    if (diff.inMinutes < 60) return ' · 已排 ${diff.inMinutes} 分钟';
    return ' · 已排 ${diff.inHours} 小时';
  }

  Widget _buildEmptyState(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ZapGlassCard(
          borderRadius: 24,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.electric_moped_rounded,
                size: 56,
                color: p.primary,
              ),
              const SizedBox(height: 14),
              Text(
                '还没有常停的电驴桩',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '扫一下车棚桩二维码或输尾号，闪雀帮你记住常用插口',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showStationEditor(
    BuildContext context, {
    ChargingStation? existing,
  }) async {
    final aliasController = TextEditingController(text: existing?.alias ?? '');
    final snController =
        TextEditingController(text: existing?.serialNumber ?? '');
    final rawUrlController =
        TextEditingController(text: existing?.rawUrl ?? '');
    final customTemplateController = TextEditingController(
      text: existing?.customDeepLinkTemplate ?? '',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final settings = ref.read(settingsProvider);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final draftStation = ChargingStation(
              id: existing?.id ?? 'preview',
              alias: aliasController.text.trim().isEmpty
                  ? '预览桩'
                  : aliasController.text.trim(),
              serialNumber: snController.text.trim().isEmpty
                  ? 'W52001715'
                  : snController.text.trim().toUpperCase(),
              rawUrl: rawUrlController.text.trim(),
              customDeepLinkTemplate:
                  customTemplateController.text.trim().isEmpty
                      ? null
                      : customTemplateController.text.trim(),
              lastUsedPort: existing?.lastUsedPort ?? 1,
              lastUsedDate: existing?.lastUsedDate ?? DateTime.now(),
            );
            final resolvedUri = UrlRuleEngine.buildTargetUri(
              draftStation,
              draftStation.lastUsedPort,
              settings,
            );

            final p = AppTheme.paletteOf(context);
            return AlertDialog(
              backgroundColor: p.modalSurface,
              title: Text(existing == null ? '新增充电桩' : '编辑充电桩'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: aliasController,
                      decoration: const InputDecoration(
                        labelText: '桩位别名',
                        hintText: '例如 B2-A区 1号桩',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: snController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        labelText: '桩号 (SN)',
                        hintText: '例如 W52001715',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: rawUrlController,
                      decoration: const InputDecoration(
                        labelText: '原始二维码链接（可选）',
                        hintText: 'http://weixin.weiyunchong.com/...',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: customTemplateController,
                      decoration: const InputDecoration(
                        labelText: '单桩独立覆盖链接 / Scheme（可选）',
                        hintText: '留空则按全局规则，支持 {SN}/{PORT}/{PORT_0}',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: p.secondaryBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: p.secondaryBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '当前生效目标链接（${settings.socketNumber(draftStation.lastUsedPort)}号口）',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: p.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            resolvedUri?.toString() ?? '无法生成有效链接，请检查规则',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: resolvedUri != null ? p.idle : p.danger,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: p.primaryFill,
                    foregroundColor: p.onPrimary,
                  ),
                  onPressed: () async {
                    final sn = snController.text.trim().toUpperCase();
                    if (sn.isEmpty) return;
                    final saved =
                        await ref.read(stationsProvider.notifier).upsertStation(
                              id: existing?.id,
                              alias: aliasController.text.trim(),
                              serialNumber: sn,
                              rawUrl: rawUrlController.text.trim(),
                              customDeepLinkTemplate:
                                  customTemplateController.text.trim(),
                              lastUsedPort: existing?.lastUsedPort ?? 1,
                            );
                    if (mounted) {
                      setState(() => _expandedStationId = saved.id);
                    }
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    aliasController.dispose();
    snController.dispose();
    rawUrlController.dispose();
    customTemplateController.dispose();
  }

  Future<void> _openLaiChongMiniProgram(BuildContext context) async {
    final uri = Uri.parse(
      'alipays://platformapi/startapp?appId=2019012363098597&page=pages%2FchargingOrder%2FchargingOrder',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('未能唤起支付宝莱充充电订单页，请确认已安装支付宝')),
        );
    }
  }

  Widget _buildReminderBanner(
    BuildContext context,
    dynamic reminder,
  ) {
    final p = AppTheme.paletteOf(context);
    final remindAt = reminder.remindAt as DateTime;
    final hh = remindAt.hour.toString().padLeft(2, '0');
    final mm = remindAt.minute.toString().padLeft(2, '0');
    final portText =
        (reminder.portLabel as String).isEmpty ? '' : ' · ${reminder.portLabel}号口';
    final isWatching = reminder.watchStationId != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ZapGlassCard(
        borderRadius: 16,
        borderColor: p.primary.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.alarm_on_rounded, color: p.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '将于 $hh:$mm 提醒去「${reminder.stationName}$portText」拔电${isWatching ? '（充完提前提醒）' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(chargingReminderProvider.notifier).clearReminder(),
              child: Text(
                '取消',
                style: TextStyle(
                  color: p.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showReminderPicker(
    BuildContext context,
    ChargingStation station,
    int watchSlot,
    String portLabel,
  ) async {
    final p = AppTheme.paletteOf(context);
    final hours = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: p.modalSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '设置电驴拔电提醒 · ${station.alias} ($portLabel号口)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '到点自动提醒；若检测到该口提前充完转空闲，闪雀也会第一时间叫你拔电',
                style: TextStyle(
                  fontSize: 12,
                  color: p.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [3, 5, 10, 12].map((h) {
                  return SizedBox(
                    width: (MediaQuery.of(sheetContext).size.width - 50) / 2,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: p.secondaryBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.of(sheetContext).pop(h),
                      icon: Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: p.primary,
                      ),
                      label: Text(
                        '$h 小时后提醒',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );

    if (hours == null || !context.mounted) return;
    await ref.read(chargingReminderProvider.notifier).setReminder(
          stationName: station.alias,
          portLabel: portLabel,
          delay: Duration(hours: hours),
          watchStationId: station.id,
          watchSlot: watchSlot,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('已设置 $hours 小时后提醒去「${station.alias}」拔电')),
      );
  }

  Future<void> _showQuickRenameDialog(
    BuildContext context,
    ChargingStation station,
  ) async {
    final result = await showDialog<({String alias, String? address})>(
      context: context,
      builder: (_) => _QuickRenameDialog(
        serialNumber: station.serialNumber,
        initialAlias: station.alias,
        initialAddress: station.address,
      ),
    );

    if (result != null) {
      await ref.read(stationsProvider.notifier).renameStation(
            station.id,
            result.alias,
            address: result.address,
          );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ChargingStation station,
  ) async {
    final p = AppTheme.paletteOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.modalSurface,
        title: const Text('删除充电桩'),
        content: Text('确认移除「${station.alias} (${station.serialNumber})」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              '删除',
              style: TextStyle(color: p.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(stationsProvider.notifier).deleteStation(station.id);
    }
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return SizedBox(
      height: 44,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: ZapGlassCard(
          borderRadius: 16,
          blurSigma: 16,
          borderColor: filled
              ? Colors.white.withValues(alpha: 0.42)
              : p.secondaryBorder,
          backgroundColors: filled
              ? [color, color.withValues(alpha: 0.92)]
              : [p.secondaryBg, p.secondaryBg],
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: filled ? textColor : color,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickRenameDialog extends StatefulWidget {
  const _QuickRenameDialog({
    required this.serialNumber,
    required this.initialAlias,
    this.initialAddress,
  });

  final String serialNumber;
  final String initialAlias;
  final String? initialAddress;

  @override
  State<_QuickRenameDialog> createState() => _QuickRenameDialogState();
}

class _QuickRenameDialogState extends State<_QuickRenameDialog> {
  late final TextEditingController _controller;
  String? _fetchedAddress;
  bool _isFetching = false;
  String? _lookupMessage;

  @override
  void initState() {
    super.initState();
    _fetchedAddress = widget.initialAddress;
    _controller = TextEditingController(text: widget.initialAlias);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetchAddress() async {
    if (_isFetching) return;
    setState(() {
      _isFetching = true;
      _lookupMessage = null;
    });
    final info = await StationLookupService.fetchStationInfo(widget.serialNumber);
    if (!mounted) return;
    setState(() {
      _isFetching = false;
      if (info != null) {
        _controller.text = info.displayName;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
        _fetchedAddress = info.fullAddress;
        _lookupMessage = '已获取：${info.fullAddress}';
      } else {
        _lookupMessage = '暂未查到该桩位置，请检查网络或手动输入';
      }
    });
  }

  void _submit() {
    Navigator.of(context).pop((
      alias: _controller.text,
      address: _fetchedAddress,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    return AlertDialog(
      backgroundColor: p.modalSurface,
      title: Text('修改名称 · ${widget.serialNumber}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: '桩位别名',
              hintText: '例如 8.4地下室靠电梯',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isFetching ? null : _fetchAddress,
              icon: _isFetching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.my_location_rounded,
                      size: 16,
                      color: p.primary,
                    ),
              label: Text(
                _isFetching ? '正在获取桩点名称...' : '自动获取桩点名称',
                style: TextStyle(
                  fontSize: 13,
                  color: p.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (_lookupMessage != null)
            Text(
              _lookupMessage!,
              style: TextStyle(
                fontSize: 11,
                color: p.textSecondary,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: p.primaryFill,
            foregroundColor: p.onPrimary,
          ),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
