import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/charging_station.dart';
import '../providers/app_providers.dart';
import '../services/launch_queue_service.dart';
import '../services/url_rule_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/quick_serial_modal.dart';
import '../widgets/station_card.dart';
import 'offline_scanner_screen.dart';
import 'rule_settings_screen.dart';

/// 主面板：实时网络状态胶囊、排队横幅、常用桩大卡片与单手底部操作栏。
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<LaunchQueueState>(launchQueueProvider, (prev, next) {
      final msg = next.statusMessage;
      if (msg != null && msg != prev?.statusMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg)));
      }
    });

    final stations = ref.watch(stationsProvider);
    final settings = ref.watch(settingsProvider);
    final queueState = ref.watch(launchQueueProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopHeader(context, ref, queueState),
            if (queueState.hasPendingTask)
              _buildActiveQueueBanner(context, ref, queueState),
            Expanded(
              child: stations.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                      itemCount: stations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final station = stations[index];
                        final isQueuedHere =
                            queueState.pendingStation?.id == station.id;
                        return StationCard(
                          station: station,
                          portCount: settings.defaultPortCount,
                          isOnline: queueState.isOnline,
                          isQueuedHere: isQueuedHere,
                          queuedPort:
                              isQueuedHere ? queueState.pendingPort : null,
                          usesPort: UrlRuleEngine.templateUsesPort(
                            station,
                            settings,
                          ),
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
                                    '已复制 ${station.serialNumber} ($port号口) 目标链接',
                                  ),
                                ),
                              );
                          },
                          onEdit: () => _showStationEditor(
                            context,
                            ref,
                            existing: station,
                          ),
                          onDelete: () => _confirmDelete(
                            context,
                            ref,
                            station,
                          ),
                        );
                      },
                    ),
            ),
            _buildBottomActionBar(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(
    BuildContext context,
    WidgetRef ref,
    LaunchQueueState queueState,
  ) {
    final isOnline = queueState.isOnline;
    final badgeColor = isOnline ? AppColors.emerald : AppColors.amber;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '闪雀',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isOnline
                      ? '外网已畅通 · 点击即可跳过广告直达'
                      : '地库无网可用 · 点选插座可先排队',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () =>
                ref.read(launchQueueProvider.notifier).refreshNetworkStatus(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: badgeColor.withValues(alpha: 0.7),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    queueState.isChecking
                        ? '检测信号中...'
                        : (isOnline ? '网络已就绪' : '地库离线模式'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: badgeColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '手动新增桩',
            onPressed: () => _showStationEditor(context, ref),
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveQueueBanner(
    BuildContext context,
    WidgetRef ref,
    LaunchQueueState queueState,
  ) {
    final station = queueState.pendingStation!;
    final port = queueState.pendingPort!;
    final isOnline = queueState.isOnline;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOnline ? AppColors.emeraldDark : AppColors.amberDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOnline ? AppColors.emerald : AppColors.amber,
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.notifications_active_rounded : Icons.wifi_off_rounded,
            color: isOnline ? AppColors.emerald : AppColors.amber,
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
                    color: isOnline ? AppColors.emerald : AppColors.amber,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${station.alias} · $port号插座${_formatQueuedElapsed(queueState.queuedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (isOnline)
            TextButton(
              onPressed: () =>
                  ref.read(launchQueueProvider.notifier).retryPendingNow(),
              child: const Text(
                '立即唤醒',
                style: TextStyle(
                  color: AppColors.emerald,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          TextButton(
            onPressed: () =>
                ref.read(launchQueueProvider.notifier).cancelQueue(),
            child: const Text(
              '取消排队',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ev_station_rounded,
              size: 64,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 14),
            Text(
              '还没有保存的充电桩',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '点击下方“离线扫新桩”或“输编号直达”即可开始使用',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: _BottomBarButton(
              icon: Icons.qr_code_scanner_rounded,
              label: '离线扫新桩',
              color: AppColors.emerald,
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
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: _BottomBarButton(
              icon: Icons.dialpad_rounded,
              label: '输编号直达',
              color: AppColors.cyan,
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
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _BottomBarButton(
              icon: Icons.tune_rounded,
              label: '规则设置',
              color: AppColors.textPrimary,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RuleSettingsScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showStationEditor(
    BuildContext context,
    WidgetRef ref, {
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

            return AlertDialog(
              backgroundColor: AppColors.surface,
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
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '当前生效目标链接（${draftStation.lastUsedPort}号口）',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            resolvedUri?.toString() ?? '无法生成有效链接，请检查规则',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: resolvedUri != null
                                  ? AppColors.emerald
                                  : AppColors.danger,
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
                    backgroundColor: AppColors.emerald,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    final sn = snController.text.trim().toUpperCase();
                    if (sn.isEmpty) return;
                    await ref.read(stationsProvider.notifier).upsertStation(
                          id: existing?.id,
                          alias: aliasController.text.trim(),
                          serialNumber: sn,
                          rawUrl: rawUrlController.text.trim(),
                          customDeepLinkTemplate:
                              customTemplateController.text.trim(),
                          lastUsedPort: existing?.lastUsedPort ?? 1,
                        );
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

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ChargingStation station,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('删除充电桩'),
        content: Text('确认移除「${station.alias} (${station.serialNumber})」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '删除',
              style: TextStyle(color: AppColors.danger),
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

class _BottomBarButton extends StatelessWidget {
  const _BottomBarButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Material(
        color: filled ? color : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: filled ? null : Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: filled ? Colors.black : color,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: filled ? Colors.black : color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
