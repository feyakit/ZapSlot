import 'package:flutter/material.dart';

import '../models/charging_station.dart';
import '../theme/app_theme.dart';

/// 充电桩大卡片：支持单手横向快选插座口（1-10）及一键唤醒 / 离线排队。
class StationCard extends StatefulWidget {
  const StationCard({
    super.key,
    required this.station,
    required this.portCount,
    required this.isOnline,
    required this.isQueuedHere,
    this.queuedPort,
    required this.onTrigger,
    required this.onEdit,
    required this.onDelete,
  });

  final ChargingStation station;
  final int portCount;
  final bool isOnline;
  final bool isQueuedHere;
  final int? queuedPort;
  final ValueChanged<int> onTrigger;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<StationCard> createState() => _StationCardState();
}

class _StationCardState extends State<StationCard> {
  late int _selectedPort;

  @override
  void initState() {
    super.initState();
    _selectedPort = widget.station.lastUsedPort.clamp(1, widget.portCount);
  }

  @override
  void didUpdateWidget(covariant StationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.station.lastUsedPort != widget.station.lastUsedPort ||
        oldWidget.portCount != widget.portCount) {
      _selectedPort = widget.station.lastUsedPort.clamp(1, widget.portCount);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomRule =
        widget.station.customDeepLinkTemplate?.trim().isNotEmpty == true;
    final accentColor = widget.isOnline ? AppColors.emerald : AppColors.amber;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: widget.isQueuedHere
              ? AppColors.amber
              : AppColors.border,
          width: widget.isQueuedHere ? 1.8 : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.station.alias,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasCustomRule) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.cyan.withValues(alpha: 0.5),
                              ),
                            ),
                            child: const Text(
                              '独立规则',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.cyan,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            widget.station.serialNumber,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.cyan,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '上次 ${widget.station.lastUsedPort}号口',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  color: AppColors.textSecondary,
                ),
                color: AppColors.surfaceElevated,
                onSelected: (value) {
                  if (value == 'edit') {
                    widget.onEdit();
                  } else if (value == 'delete') {
                    widget.onDelete();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('编辑桩信息 / 独立规则'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.danger,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '删除充电桩',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '选择插座编号',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.portCount,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final port = index + 1;
                final isSelected = port == _selectedPort;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selectedPort = port),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accentColor.withValues(alpha: 0.22)
                          : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? accentColor : AppColors.border,
                        width: isSelected ? 1.8 : 1,
                      ),
                    ),
                    child: Text(
                      '$port',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color:
                            isSelected ? accentColor : AppColors.textPrimary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.isQueuedHere
                    ? AppColors.amberDark
                    : accentColor,
                foregroundColor:
                    widget.isQueuedHere ? AppColors.amber : Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: widget.isQueuedHere
                      ? const BorderSide(color: AppColors.amber, width: 1.5)
                      : BorderSide.none,
                ),
              ),
              onPressed: () => widget.onTrigger(_selectedPort),
              icon: Icon(
                widget.isQueuedHere
                    ? Icons.hourglass_top_rounded
                    : (widget.isOnline
                        ? Icons.bolt_rounded
                        : Icons.schedule_send_rounded),
                size: 22,
              ),
              label: Text(
                widget.isQueuedHere
                    ? '排队中 (${widget.queuedPort ?? _selectedPort}号口) · 点此更新'
                    : (widget.isOnline
                        ? '一键唤醒 · $_selectedPort号口'
                        : '离线排队 · $_selectedPort号口'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
