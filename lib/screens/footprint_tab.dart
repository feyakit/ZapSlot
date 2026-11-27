import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/charging_history_provider.dart';
import '../providers/charging_reminder_provider.dart';
import '../theme/app_theme.dart';

/// Tab 2：充电足迹、拔枪提醒监控与莱充官方订单入口（全透明液态玻璃风）。
class FootprintTab extends ConsumerWidget {
  const FootprintTab({
    super.key,
    required this.onOpenMiniProgram,
  });

  final VoidCallback onOpenMiniProgram;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppTheme.paletteOf(context);
    final reminder = ref.watch(chargingReminderProvider);
    final history = ref.watch(chargingHistoryProvider);

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
                    '足迹与订单',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: p.textPrimary,
                    ),
                  ),
                ),
                if (history.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      ref.read(chargingHistoryProvider.notifier).clearAll();
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
                                    '将于 ${reminder.remindAt.hour.toString().padLeft(2, '0')}:${reminder.remindAt.minute.toString().padLeft(2, '0')} 提醒拔枪',
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
                                '我已拔枪',
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
                                '暂无拔枪提醒 · 在充电页卡片右下角点 ⏰ 即可设置定时或充完自动提醒',
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
                // 2. 一键打开莱充小程序查官方订单 / 停充
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
                      onOpenMiniProgram();
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
                const SizedBox(height: 18),
                Text(
                  '本地充电足迹',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                if (history.isEmpty)
                  ZapGlassCard(
                    borderRadius: 20,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 32,
                    ),
                    child: Center(
                      child: Text(
                        '暂无直达记录 · 每次点选插口去充电会自动记录在这里',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                  )
                else
                  ZapGlassCard(
                    borderRadius: 20,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: history.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, idx) {
                        final item = history[idx];
                        final dt = item.triggeredAt;
                        final timeStr =
                            '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                        return ListTile(
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
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: p.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            '${item.serialNumber} · $timeStr',
                            style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                            ),
                          ),
                        );
                      },
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
