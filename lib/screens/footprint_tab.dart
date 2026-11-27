import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../providers/charging_history_provider.dart';
import '../providers/charging_reminder_provider.dart';
import '../services/charging_stats_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// Tab 2：充电足迹、周/月/全量统计分析、常用金额记账与莱充官方订单入口（全透明液态玻璃风）。
class FootprintTab extends ConsumerStatefulWidget {
  const FootprintTab({
    super.key,
    required this.onOpenMiniProgram,
  });

  final VoidCallback onOpenMiniProgram;

  @override
  ConsumerState<FootprintTab> createState() => _FootprintTabState();
}

class _FootprintTabState extends ConsumerState<FootprintTab> {
  StatsScope _scope = StatsScope.week;

  String _formatYuan(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    final oneDec = double.parse(value.toStringAsFixed(1));
    if (oneDec == value) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final reminder = ref.watch(chargingReminderProvider);
    final history = ref.watch(chargingHistoryProvider);
    final commonAmounts = ref.watch(
      settingsProvider.select((s) => s.commonChargeAmounts),
    );
    final stats = ChargingStats.fromRecords(history, scope: _scope);
    final recentItems = history.take(30).toList();

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '足迹与统计',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: p.textPrimary,
                    ),
                  ),
                ),
                if (history.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      HapticFeedback.selectionClick();
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          backgroundColor: p.modalSurface,
                          title: const Text('清空全部足迹'),
                          content: Text(
                            '确定清空全部 ${history.length} 条充电足迹与记账统计吗？此操作不可撤销。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: Text(
                                '清空',
                                style: TextStyle(color: p.danger),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await ref
                            .read(chargingHistoryProvider.notifier)
                            .clearAll();
                      }
                    },
                    child: Text(
                      '清空足迹',
                      style: TextStyle(color: p.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              children: [
                // 1. 当前拔枪提醒 / 充完监测状态卡
                ZapGlassCard(
                  borderRadius: 22,
                  borderColor: reminder != null
                      ? p.primary.withValues(alpha: 0.65)
                      : p.glassBorder,
                  padding: const EdgeInsets.all(14),
                  child: reminder != null
                      ? Row(
                          children: [
                            Icon(
                              Icons.alarm_on_rounded,
                              color: p.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '将于 ${reminder.remindAt.hour.toString().padLeft(2, '0')}:${reminder.remindAt.minute.toString().padLeft(2, '0')} 提醒拔电',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${reminder.stationName}${reminder.portLabel.isEmpty ? '' : ' · ${reminder.portLabel}号口'}${reminder.watchStationId != null ? '（充完提前提醒）' : ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: p.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: p.secondaryBorder),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                ref
                                    .read(chargingReminderProvider.notifier)
                                    .clearReminder();
                              },
                              child: Text(
                                '我已拔电',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: p.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Icon(
                              Icons.alarm_add_rounded,
                              color: p.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '暂无拔电提醒 · 在充电页点闹钟，到点或充完闪雀自动叫你',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: p.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                // 2. 一键直达莱充充电订单页
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: p.primaryFill,
                      foregroundColor: p.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      widget.onOpenMiniProgram();
                    },
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text(
                      '打开莱充小程序（查官方订单 / 停充）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    '充电统计与习惯分析',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildAnalyticsCard(p, stats),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      '本地充电足迹',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: p.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    if (history.isNotEmpty)
                      Text(
                        '点记录可记账 · 共 ${history.length} 条',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: p.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (recentItems.isEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ZapGlassCard(
                      borderRadius: 22,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 32,
                      ),
                      child: Center(
                        child: Text(
                          '暂无直达记录 · 每次点选插口去充电会自动记录在这里并生成统计分析',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: p.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ZapGlassCard(
                      borderRadius: 22,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var idx = 0; idx < recentItems.length; idx++) ...[
                            if (idx > 0) const Divider(height: 1),
                            Builder(
                              builder: (_) {
                                final item = recentItems[idx];
                                final dt = item.triggeredAt;
                                final timeStr =
                                    '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                                final hasAmount = item.amountYuan != null &&
                                    item.amountYuan! > 0;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 2,
                                  ),
                                  onTap: () => _showAmountPickerSheet(
                                    context,
                                    ref,
                                    index: idx,
                                    record: item,
                                    initialPresets: commonAmounts,
                                  ),
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: p.primary.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.bolt_rounded,
                                      color: p.primary,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    '${item.stationAlias} · ${item.socketLabel}号口',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: p.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${item.serialNumber} · $timeStr',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: p.textSecondary,
                                    ),
                                  ),
                                  trailing: Container(
                                    width: 72,
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: hasAmount
                                          ? p.primary.withValues(alpha: 0.15)
                                          : p.secondaryBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: hasAmount
                                            ? p.primary.withValues(alpha: 0.4)
                                            : p.secondaryBorder,
                                      ),
                                    ),
                                    child: Text(
                                      hasAmount
                                          ? '¥${_formatYuan(item.amountYuan!)}'
                                          : '+ 记金额',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: hasAmount
                                            ? p.primary
                                            : p.textSecondary,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
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

  Future<void> _showAmountPickerSheet(
    BuildContext context,
    WidgetRef ref, {
    required int index,
    required ChargingHistoryRecord record,
    required List<double> initialPresets,
  }) async {
    final p = AppTheme.paletteOf(context);
    var presets = [...initialPresets];
    var isEditingPresets = false;
    final customAmountController = TextEditingController(
      text: record.amountYuan != null ? _formatYuan(record.amountYuan!) : '',
    );
    final newPresetController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.modalSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '记录花费 · ${record.stationAlias} (${record.socketLabel}号口)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setSheetState(
                              () => isEditingPresets = !isEditingPresets,
                            );
                          },
                          child: Text(
                            isEditingPresets ? '完成编辑' : '自定义常用',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: p.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presets.map((amount) {
                        final label = '${_formatYuan(amount)}元';
                        if (isEditingPresets) {
                          return InputChip(
                            label: Text(label),
                            deleteIcon: const Icon(Icons.close_rounded, size: 16),
                            onDeleted: presets.length <= 1
                                ? null
                                : () async {
                                    final next = [...presets]..remove(amount);
                                    setSheetState(() => presets = next);
                                    await ref
                                        .read(settingsProvider.notifier)
                                        .updateCommonChargeAmounts(next);
                                  },
                          );
                        }
                        final isSelected = record.amountYuan == amount;
                        return ChoiceChip(
                          label: Text(
                            label,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: isSelected ? p.onPrimary : p.textPrimary,
                            ),
                          ),
                          selected: isSelected,
                          selectedColor: p.primaryFill,
                          backgroundColor: p.secondaryBg,
                          side: BorderSide(
                            color: isSelected ? p.primary : p.secondaryBorder,
                          ),
                          onSelected: (_) async {
                            HapticFeedback.selectionClick();
                            await ref
                                .read(chargingHistoryProvider.notifier)
                                .updateRecordAmount(index, amount);
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                        );
                      }).toList(),
                    ),
                    if (isEditingPresets) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: newPresetController,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: '新增常用金额（元）',
                                hintText: '例如 1.2 或 2.5',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () async {
                                final parsed = double.tryParse(
                                  newPresetController.text.trim(),
                                );
                                if (parsed == null ||
                                    parsed <= 0 ||
                                    parsed > 999) {
                                  return;
                                }
                                final next = {...presets, parsed}.toList()
                                  ..sort();
                                setSheetState(() {
                                  presets = next;
                                  newPresetController.clear();
                                });
                                await ref
                                    .read(settingsProvider.notifier)
                                    .updateCommonChargeAmounts(next);
                              },
                              child: const Text('添加并保存'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: customAmountController,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: '本次实际花费（元）',
                                hintText: '例如 1.50',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: () async {
                                final parsed = double.tryParse(
                                  customAmountController.text.trim(),
                                );
                                if (parsed == null || parsed <= 0) return;
                                await ref
                                    .read(chargingHistoryProvider.notifier)
                                    .updateRecordAmount(index, parsed);
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              },
                              child: const Text('保存金额'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (record.amountYuan != null)
                            TextButton(
                              onPressed: () async {
                                await ref
                                    .read(chargingHistoryProvider.notifier)
                                    .updateRecordAmount(index, null);
                                if (sheetContext.mounted) {
                                  Navigator.of(sheetContext).pop();
                                }
                              },
                              child: Text(
                                '清除金额',
                                style: TextStyle(color: p.textSecondary),
                              ),
                            ),
                          TextButton(
                            onPressed: () async {
                              await ref
                                  .read(chargingHistoryProvider.notifier)
                                  .deleteRecord(index);
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                            },
                            child: Text(
                              '删除此条足迹',
                              style: TextStyle(color: p.danger),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    customAmountController.dispose();
    newPresetController.dispose();
  }

  Widget _buildAnalyticsCard(ZapPalette p, ChargingStats stats) {
    final maxBar = stats.periodBars.fold<int>(
      1,
      (prev, e) => e.count > prev ? e.count : prev,
    );
    final hasAnySpend = stats.allTimeSpend > 0;
    final trendTitle = switch (_scope) {
      StatsScope.week => '本周每日频次',
      StatsScope.month => '本月每周趋势',
      StatsScope.all => '近 6 个月度统计',
    };
    final trendSummary = switch (_scope) {
      StatsScope.week =>
        '本周 ${stats.thisWeekCount} 次${stats.thisWeekSpend > 0 ? ' · ¥${_formatYuan(stats.thisWeekSpend)}' : ''}',
      StatsScope.month =>
        '本月 ${stats.thisMonthCount} 次${stats.thisMonthSpend > 0 ? ' · ¥${_formatYuan(stats.thisMonthSpend)}' : ''}',
      StatsScope.all =>
        '累计 ${stats.allTimeCount} 次${stats.allTimeSpend > 0 ? ' · ¥${_formatYuan(stats.allTimeSpend)}' : ''}',
    };

    return ZapGlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 0. 周 / 月 / 全部 切换
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<StatsScope>(
              segments: const [
                ButtonSegment(value: StatsScope.week, label: Text('本周')),
                ButtonSegment(value: StatsScope.month, label: Text('本月')),
                ButtonSegment(value: StatsScope.all, label: Text('全部')),
              ],
              selected: {_scope},
              onSelectionChanged: (values) {
                HapticFeedback.selectionClick();
                setState(() => _scope = values.first);
              },
            ),
          ),
          const SizedBox(height: 12),
          // 1. 次数 KPI（本周 / 本月 / 累计）
          Row(
            children: [
              _StatKpiTile(
                p: p,
                label: '本周充电',
                value: '${stats.thisWeekCount}次',
                accent: p.primary,
              ),
              const SizedBox(width: 8),
              _StatKpiTile(
                p: p,
                label: '本月充电',
                value: '${stats.thisMonthCount}次',
                accent: p.idle,
              ),
              const SizedBox(width: 8),
              _StatKpiTile(
                p: p,
                label: '累计足迹',
                value: '${stats.allTimeCount}次',
                accent: p.busy,
              ),
            ],
          ),
          if (hasAnySpend) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _StatKpiTile(
                  p: p,
                  label: '本周花费',
                  value: '¥${_formatYuan(stats.thisWeekSpend)}',
                  accent: p.primary,
                ),
                const SizedBox(width: 8),
                _StatKpiTile(
                  p: p,
                  label: '本月花费',
                  value: '¥${_formatYuan(stats.thisMonthSpend)}',
                  accent: p.idle,
                ),
                const SizedBox(width: 8),
                _StatKpiTile(
                  p: p,
                  label: '单次均价',
                  value: stats.averageSpend != null
                      ? '¥${_formatYuan(stats.averageSpend!)}'
                      : '--',
                  accent: p.busy,
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          // 2. 最常用桩位 + 最顺手插口
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: p.secondaryBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.secondaryBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.electric_moped_rounded, size: 18, color: p.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '最常去：${stats.topStationName ?? '--'}${stats.totalCount > 0 ? ' (${stats.topStationPercent}%)' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '偏好 ${stats.topSocketLabel ?? '--'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: p.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 3. 周 / 月 / 月度趋势柱状图
          Row(
            children: [
              Text(
                trendTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: p.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                trendSummary,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: p.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: stats.periodBars.map((bar) {
                final barRatio = bar.count == 0 ? 0.0 : (bar.count / maxBar);
                final barHeight = 8.0 + (barRatio * 28.0);
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (bar.count > 0)
                        Text(
                          '${bar.count}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: bar.isCurrent ? p.primary : p.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 3),
                      Container(
                        width: 16,
                        height: bar.count == 0 ? 6 : barHeight,
                        decoration: BoxDecoration(
                          color: bar.count == 0
                              ? p.secondaryBorder
                              : (bar.isCurrent
                                  ? p.primary
                                  : p.primary.withValues(alpha: 0.55)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        bar.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight:
                              bar.isCurrent ? FontWeight.w800 : FontWeight.w600,
                          color: bar.isCurrent ? p.primary : p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          // 4. 充电时段分布
          Text(
            '充电时段分布',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final bucket in stats.timeBuckets) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      bucket.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: bucket.ratio,
                        minHeight: 8,
                        backgroundColor: p.secondaryBg,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          bucket.count > 0
                              ? p.primary.withValues(alpha: 0.85)
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${bucket.count}次',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatKpiTile extends StatelessWidget {
  const _StatKpiTile({
    required this.p,
    required this.label,
    required this.value,
    required this.accent,
  });

  final ZapPalette p;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: p.secondaryBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.secondaryBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: p.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
