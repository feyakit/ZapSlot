import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/charging_station.dart';
import '../services/station_lookup_service.dart';
import '../theme/app_theme.dart';

/// 液态玻璃风充电桩卡片（支持手风琴展开/自动闭合）：
/// - 折叠态：紧凑展示名称、空闲胶囊、桩号与上次插口，点击即展开并自动收起其他卡片；
/// - 展开态：5×2 透明玻璃插口格、单行智能状态条、选号直达与定时提醒。
class StationCard extends StatefulWidget {
  const StationCard({
    super.key,
    required this.station,
    required this.portCount,
    required this.isOnline,
    required this.isQueuedHere,
    this.queuedPort,
    this.usesPort = false,
    this.portIndexBase = 0,
    required this.onTrigger,
    required this.onCopyLink,
    required this.onEdit,
    required this.onDelete,
    this.onRename,
    this.liveInfo,
    this.isRefreshing = false,
    this.isFirst = false,
    this.isExpanded = true,
    this.onToggleExpand,
    this.onRefreshLive,
    this.onPinToTop,
    this.onScheduleReminder,
    this.onOpenMiniProgram,
  });

  final ChargingStation station;
  final int portCount;
  final bool isOnline;
  final bool isQueuedHere;
  final int? queuedPort;
  final bool usesPort;
  final int portIndexBase;
  final Future<void> Function(int port) onTrigger;
  final ValueChanged<int> onCopyLink;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onRename;
  final StationLiveInfo? liveInfo;
  final bool isRefreshing;
  final bool isFirst;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;
  final VoidCallback? onRefreshLive;
  final VoidCallback? onPinToTop;
  final ValueChanged<int>? onScheduleReminder;
  final VoidCallback? onOpenMiniProgram;

  @override
  State<StationCard> createState() => _StationCardState();
}

class _StationCardState extends State<StationCard> {
  late int _selectedPort;
  bool _isSubmitting = false;

  String _socket(int port) =>
      widget.station.socketLabel(port, widget.portIndexBase);

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

  Future<void> _handleTrigger() async {
    if (_isSubmitting) return;
    HapticFeedback.mediumImpact();

    final p = AppTheme.paletteOf(context);
    final detail = widget.liveInfo?.gunDetails[_selectedPort];
    if (widget.isOnline &&
        detail != null &&
        (detail.status == GunWorkStatus.busy ||
            detail.status == GunWorkStatus.fault)) {
      final statusName =
          detail.status == GunWorkStatus.fault ? '故障/维护中' : '正在充电占用中';
      final remText = detail.remainingMinutes > 0
          ? '（预计还剩 ${_formatMinutes(detail.remainingMinutes)}）'
          : '';
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${_socket(_selectedPort)}号口$statusName'),
          content: Text(
            '云端状态显示该插口当前$statusName$remText，确定仍要继续打开支付吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('换个空闲口'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: p.offline,
                foregroundColor: p.onOffline,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('仍要继续'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.onTrigger(_selectedPort);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h小时' : '$h小时$m分';
  }

  String _formatRelativeTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 2) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${date.month}/${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final live = widget.liveInfo;

    return ZapGlassCard(
      borderRadius: 24,
      borderColor: widget.isQueuedHere ? p.offline : p.glassBorder,
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        widget.isExpanded ? 16 : 14,
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: widget.isExpanded
            ? _buildExpandedBody(p, live)
            : _buildCollapsedBody(p, live),
      ),
    );
  }

  Widget _buildCollapsedBody(ZapPalette p, StationLiveInfo? live) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onToggleExpand?.call();
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.station.alias,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: p.textPrimary,
                    letterSpacing: 0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.station.serialNumber} · 上次 ${_socket(widget.station.lastUsedPort)}号口 · ${_formatRelativeTime(widget.station.lastUsedDate)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: p.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (live != null && (live.isDeviceOffline || live.totalCount > 0))
            _buildIdleBadge(p, live),
          if (widget.onToggleExpand != null) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: p.textSecondary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedBody(ZapPalette p, StationLiveInfo? live) {
    final hasCustomRule =
        widget.station.customDeepLinkTemplate?.trim().isNotEmpty == true;
    final actionBg = widget.isOnline ? p.primaryFill : p.offline;
    final actionFg = widget.isOnline ? p.onPrimary : p.onOffline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 第 1 行：桩标题 + 空闲胶囊 + 折叠/菜单
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.onRename == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        widget.onRename!();
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.station.alias,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: p.textPrimary,
                            letterSpacing: 0.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.onRename != null) ...[
                        const SizedBox(width: 5),
                        Icon(
                          Icons.edit_rounded,
                          size: 14,
                          color: p.textSecondary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (live != null && (live.isDeviceOffline || live.totalCount > 0))
              _buildIdleBadge(p, live),
            if (hasCustomRule)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: p.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '独立规则',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: p.primary,
                  ),
                ),
              ),
            if (widget.onToggleExpand != null)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onToggleExpand!();
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: p.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            SizedBox(
              width: 32,
              height: 32,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: p.textSecondary,
                  size: 20,
                ),
                color: p.modalSurface,
                onSelected: (value) {
                  if (value == 'pin') {
                    widget.onPinToTop?.call();
                  } else if (value == 'reminder') {
                    widget.onScheduleReminder?.call(_selectedPort);
                  } else if (value == 'mini_program') {
                    widget.onOpenMiniProgram?.call();
                  } else if (value == 'copy_link') {
                    widget.onCopyLink(_selectedPort);
                  } else if (value == 'edit') {
                    widget.onEdit();
                  } else if (value == 'delete') {
                    widget.onDelete();
                  }
                },
                itemBuilder: (context) => [
                  if (!widget.isFirst && widget.onPinToTop != null)
                    PopupMenuItem(
                      value: 'pin',
                      child: _buildMenuRow(
                        icon: Icons.vertical_align_top_rounded,
                        color: p.primary,
                        label: '置顶此充电桩',
                      ),
                    ),
                  if (widget.onScheduleReminder != null)
                    PopupMenuItem(
                      value: 'reminder',
                      child: _buildMenuRow(
                        icon: Icons.alarm_add_rounded,
                        color: p.primary,
                        label: '设置取车 / 结束提醒',
                      ),
                    ),
                  if (widget.onOpenMiniProgram != null)
                    PopupMenuItem(
                      value: 'mini_program',
                      child: _buildMenuRow(
                        icon: Icons.receipt_long_rounded,
                        color: p.idle,
                        label: '打开莱充查订单 / 停充',
                      ),
                    ),
                  PopupMenuItem(
                    value: 'copy_link',
                    child: _buildMenuRow(
                      icon: Icons.link_rounded,
                      color: p.textSecondary,
                      label: '复制目标链接',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: _buildMenuRow(
                      icon: Icons.edit_rounded,
                      color: p.textSecondary,
                      label: '编辑桩信息 / 独立规则',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: _buildMenuRow(
                      icon: Icons.delete_rounded,
                      color: p.danger,
                      label: '删除充电桩',
                      labelColor: p.danger,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 第 2 行：桩号 +（云端桩点名或上次使用时间）
        Row(
          children: [
            Text(
              widget.station.serialNumber,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: p.primary,
                letterSpacing: 0.5,
              ),
            ),
            if (widget.station.address?.trim().isNotEmpty == true &&
                widget.station.address!.trim() !=
                    widget.station.alias.trim()) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.place_rounded,
                size: 13,
                color: p.idle,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  widget.station.address!,
                  style: TextStyle(
                    fontSize: 12,
                    color: p.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '上次 ${_socket(widget.station.lastUsedPort)}号口 · ${_formatRelativeTime(widget.station.lastUsedDate)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: p.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // 核心区：5×2 透明玻璃插口格
        _buildSocketGrid(p),
        const SizedBox(height: 10),
        // 单行智能状态条
        _buildBottomMetaBar(p, live),
        const SizedBox(height: 12),
        // 底部主操作区
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isQueuedHere
                        ? p.offline.withValues(alpha: 0.22)
                        : actionBg,
                    foregroundColor: widget.isQueuedHere ? p.offline : actionFg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: widget.isQueuedHere
                          ? BorderSide(color: p.offline, width: 1.5)
                          : BorderSide(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _handleTrigger,
                  icon: _isSubmitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: widget.isQueuedHere ? p.offline : actionFg,
                          ),
                        )
                      : Icon(
                          widget.isQueuedHere
                              ? Icons.hourglass_top_rounded
                              : (widget.isOnline
                                  ? Icons.bolt_rounded
                                  : Icons.schedule_send_rounded),
                          size: 20,
                        ),
                  label: Text(
                    _isSubmitting
                        ? '正在检测信号...'
                        : (widget.isQueuedHere
                            ? '排队中 (${_socket(widget.queuedPort ?? _selectedPort)}号口) · 点此更新'
                            : (widget.isOnline
                                ? (widget.usesPort
                                    ? '选号直达支付 · ${_socket(_selectedPort)}号口'
                                    : '打开充电页 · ${_socket(_selectedPort)}号口')
                                : '离线排队 · ${_socket(_selectedPort)}号口')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.onScheduleReminder != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 50,
                height: 50,
                child: Tooltip(
                  message: '定时提醒 / 充完监测',
                  child: Material(
                    color: p.secondaryBg,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onScheduleReminder!(_selectedPort);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: p.secondaryBorder),
                        ),
                        child: Icon(
                          Icons.alarm_add_rounded,
                          color: p.primary,
                          size: 21,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildIdleBadge(ZapPalette p, StationLiveInfo live) {
    final badgeColor = live.isDeviceOffline ? p.danger : p.idle;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withValues(alpha: 0.32)),
      ),
      child: Text(
        live.isDeviceOffline
            ? '设备离线'
            : '${live.idleCount}/${live.totalCount}空闲',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: badgeColor,
        ),
      ),
    );
  }

  String? _selectedSocketDetailText() {
    final detail = widget.liveInfo?.gunDetails[_selectedPort];
    if (detail == null) return null;
    if (detail.status != GunWorkStatus.busy &&
        detail.remainingMinutes <= 0 &&
        (detail.currentValue.isEmpty || detail.currentValue == '0')) {
      return null;
    }
    final curNum = double.tryParse(detail.currentValue);
    final curText = (curNum != null && curNum > 0)
        ? (curNum >= 100
            ? '${(curNum / 1000).toStringAsFixed(2)}A'
            : '${detail.currentValue}A')
        : null;
    final parts = <String>[
      if (detail.status == GunWorkStatus.busy) '充电中',
      if (curText != null) '电流 $curText',
      if (detail.remainingMinutes > 0)
        '剩余 ${_formatMinutes(detail.remainingMinutes)}',
    ];
    if (parts.isEmpty) return null;
    return '${_socket(_selectedPort)}号口 · ${parts.join(' · ')}';
  }

  Widget _buildBottomMetaBar(ZapPalette p, StationLiveInfo? info) {
    final busyDetail = _selectedSocketDetailText();
    if (busyDetail != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: p.busy.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.busy.withValues(alpha: 0.38)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.electric_meter_rounded,
              size: 14,
              color: p.busy,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                busyDetail,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: p.busy,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildRefreshButton(p),
          ],
        ),
      );
    }

    final feePart = info?.electricityFees != null
        ? '${info!.electricityFees!.toStringAsFixed(info.electricityFees! % 1 == 0 ? 0 : 1)}元/度'
        : null;
    final pkgPart = (info?.packages.isNotEmpty == true)
        ? info!.packages.take(2).join(' · ')
        : null;

    final metaParts = <String>[
      '上次 ${_socket(widget.station.lastUsedPort)}号口 (${_formatRelativeTime(widget.station.lastUsedDate)})',
      if (info?.supportsFullSelfStop == true) '充满自停',
      if (feePart != null) feePart,
      if (pkgPart != null) pkgPart,
    ];

    return Row(
      children: [
        Expanded(
          child: Text(
            metaParts.join(' · '),
            style: TextStyle(
              fontSize: 11,
              color: p.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (info != null && !widget.isOnline)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              '离线缓存',
              style: TextStyle(
                fontSize: 10,
                color: p.busy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        _buildRefreshButton(p),
      ],
    );
  }

  Widget _buildRefreshButton(ZapPalette p) {
    if (widget.onRefreshLive == null) return const SizedBox.shrink();
    return InkWell(
      onTap: widget.isRefreshing ? null : widget.onRefreshLive,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: widget.isRefreshing
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              )
            : Icon(
                Icons.refresh_rounded,
                size: 15,
                color: p.textSecondary,
              ),
      ),
    );
  }

  Widget _buildSocketGrid(ZapPalette p) {
    const columns = 5;
    final rowCount = (widget.portCount + columns - 1) ~/ columns;
    final gunStatuses = widget.liveInfo?.gunStatuses;

    return Column(
      children: List.generate(rowCount, (rowIndex) {
        return Padding(
          padding: EdgeInsets.only(bottom: rowIndex == rowCount - 1 ? 0 : 8),
          child: Row(
            children: List.generate(columns, (colIndex) {
              final port = rowIndex * columns + colIndex + 1;
              if (port > widget.portCount) {
                return const Expanded(child: SizedBox.shrink());
              }
              final isSelected = port == _selectedPort;
              final gunStatus = gunStatuses?[port];
              final isBusy = gunStatus == GunWorkStatus.busy;
              final dotColor = switch (gunStatus) {
                GunWorkStatus.idle => p.idle,
                GunWorkStatus.busy => p.busy,
                GunWorkStatus.fault => p.danger,
                _ => null,
              };

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: colIndex == columns - 1 ? 0 : 8,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedPort = port);
                      },
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        setState(() => _selectedPort = port);
                        widget.onCopyLink(port);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? p.primary.withValues(alpha: 0.16)
                              : (isBusy ? p.slotBusyBg : p.slotBg),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? p.primary : p.secondaryBorder,
                            width: isSelected ? 1.8 : 1,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Center(
                              child: Text(
                                _socket(port),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? p.primary
                                      : (isBusy
                                          ? p.textSecondary
                                          : p.textPrimary),
                                ),
                              ),
                            ),
                            if (dotColor != null)
                              Positioned(
                                top: 5,
                                right: 6,
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: dotColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildMenuRow({
    required IconData icon,
    required Color color,
    required String label,
    Color? labelColor,
  }) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
      ],
    );
  }
}
