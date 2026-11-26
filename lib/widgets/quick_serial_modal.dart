import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../providers/app_providers.dart';
import '../services/url_rule_engine.dart';
import '../theme/app_theme.dart';

/// 输编号直达弹窗：支持大按钮数字键盘快速输入后 4 位桩号，或切换完整输入模式。
class QuickSerialModal extends ConsumerStatefulWidget {
  const QuickSerialModal({super.key});

  @override
  ConsumerState<QuickSerialModal> createState() => _QuickSerialModalState();
}

class _QuickSerialModalState extends ConsumerState<QuickSerialModal> {
  String _suffixDigits = '';
  bool _manualMode = false;
  bool _portManuallySelected = false;
  String? _lastSyncedStationId;
  late TextEditingController _manualController;
  int _selectedPort = 1;

  @override
  void initState() {
    super.initState();
    final prefix = ref.read(settingsProvider).quickInputPrefix;
    _manualController = TextEditingController(text: prefix);
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  String _currentSerial(String prefix) {
    if (_manualMode) {
      return _manualController.text.trim().toUpperCase();
    }
    return '$prefix$_suffixDigits'.toUpperCase();
  }

  void _syncMatchedStationPort(String prefix) {
    if (_portManuallySelected) return;
    final serial = _currentSerial(prefix);
    final stations = ref.read(stationsProvider);
    final matched =
        stations.where((s) => s.serialNumber == serial).firstOrNull;
    if (matched != null && matched.id != _lastSyncedStationId) {
      final maxPort = ref.read(settingsProvider).defaultPortCount;
      _selectedPort = matched.lastUsedPort.clamp(1, maxPort);
      _lastSyncedStationId = matched.id;
    } else if (matched == null) {
      _lastSyncedStationId = null;
    }
  }

  void _appendDigit(String digit, String prefix) {
    if (_suffixDigits.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      _suffixDigits += digit;
      _syncMatchedStationPort(prefix);
    });
  }

  void _backspace(String prefix) {
    if (_suffixDigits.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _suffixDigits = _suffixDigits.substring(0, _suffixDigits.length - 1);
      _syncMatchedStationPort(prefix);
    });
  }

  Future<void> _submit() async {
    HapticFeedback.mediumImpact();
    final settings = ref.read(settingsProvider);
    final rawSn = _currentSerial(settings.quickInputPrefix);
    final extracted = UrlRuleEngine.extractSerialNumber(
      rawSn,
      regexPattern: settings.serialRegex,
    );
    final finalSn = extracted ?? rawSn;

    if (finalSn.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请补全 4 位尾号或输入完整桩号')),
      );
      return;
    }

    final stations = ref.read(stationsProvider);
    final existing =
        stations.where((s) => s.serialNumber == finalSn).firstOrNull;

    final station = existing ??
        await ref.read(stationsProvider.notifier).upsertStation(
              alias: '车库桩 ${finalSn.substring(finalSn.length - 4)}',
              serialNumber: finalSn,
              rawUrl: UrlRuleEngine.previewUrl(
                AppSettings.defaultFallbackRawUrlTemplate,
                sampleSn: finalSn,
                samplePort: _selectedPort,
              ),
              lastUsedPort: _selectedPort,
            );

    final outcome = await ref
        .read(launchQueueProvider.notifier)
        .triggerOrQueue(station, _selectedPort);

    if (!mounted) return;
    Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final stations = ref.watch(stationsProvider);
    final queueState = ref.watch(launchQueueProvider);

    final prefix = settings.quickInputPrefix;
    final serial = _currentSerial(prefix);
    final matched =
        stations.where((s) => s.serialNumber == serial).firstOrNull;
    final isReady = _manualMode
        ? serial.length >= 5
        : _suffixDigits.length == 4;

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '输编号直达',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _manualMode = !_manualMode;
                        if (_manualMode) {
                          _manualController.text = serial;
                        }
                      });
                    },
                    icon: Icon(
                      _manualMode
                          ? Icons.dialpad_rounded
                          : Icons.keyboard_alt_outlined,
                      size: 18,
                      color: AppColors.cyan,
                    ),
                    label: Text(
                      _manualMode ? '切回尾号键盘' : '完整输入',
                      style: const TextStyle(color: AppColors.cyan),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!_manualMode)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isReady ? AppColors.cyan : AppColors.border,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        prefix,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      for (var i = 0; i < 4; i++) ...[
                        Container(
                          width: 36,
                          height: 44,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: i < _suffixDigits.length
                                  ? AppColors.cyan
                                  : AppColors.border,
                            ),
                          ),
                          child: Text(
                            i < _suffixDigits.length ? _suffixDigits[i] : '•',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: i < _suffixDigits.length
                                  ? AppColors.cyan
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                TextField(
                  controller: _manualController,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    labelText: '完整充电桩编号',
                    hintText: '例如 W52001715',
                  ),
                  onChanged: (_) => setState(() {
                    _syncMatchedStationPort(prefix);
                  }),
                ),
              if (matched != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '已匹配保存桩：${matched.alias}（上次 ${matched.lastUsedPort}号口）',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.emerald,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                '插座编号',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: settings.defaultPortCount,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final port = index + 1;
                    final selected = port == _selectedPort;
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedPort = port;
                          _portManuallySelected = true;
                        });
                      },
                      child: Container(
                        width: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.cyan.withValues(alpha: 0.2)
                              : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected ? AppColors.cyan : AppColors.border,
                            width: selected ? 1.6 : 1,
                          ),
                        ),
                        child: Text(
                          '$port',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? AppColors.cyan
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (!_manualMode) ...[
                const SizedBox(height: 16),
                _buildKeypad(prefix),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: queueState.isOnline
                        ? AppColors.emerald
                        : AppColors.amber,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: isReady ? _submit : null,
                  icon: Icon(
                    queueState.isOnline
                        ? Icons.bolt_rounded
                        : Icons.schedule_send_rounded,
                  ),
                  label: Text(
                    queueState.isOnline
                        ? '立即直达 · $_selectedPort号口'
                        : '加入离线排队 · $_selectedPort号口',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad(String prefix) {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['清空', '0', '退格'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: row.map((key) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    height: 52,
                    child: Material(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (key == '清空') {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _suffixDigits = '';
                              _syncMatchedStationPort(prefix);
                            });
                          } else if (key == '退格') {
                            _backspace(prefix);
                          } else {
                            _appendDigit(key, prefix);
                          }
                        },
                        child: Center(
                          child: key == '退格'
                              ? const Icon(
                                  Icons.backspace_outlined,
                                  color: AppColors.textPrimary,
                                  size: 20,
                                )
                              : Text(
                                  key,
                                  style: TextStyle(
                                    fontSize: key == '清空' ? 15 : 22,
                                    fontWeight: FontWeight.w700,
                                    color: key == '清空'
                                        ? AppColors.textSecondary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
