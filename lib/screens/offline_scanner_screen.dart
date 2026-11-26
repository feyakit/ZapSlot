import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../providers/app_providers.dart';
import '../services/url_rule_engine.dart';
import '../theme/app_theme.dart';

enum ScannerMode { qr, ocr }

/// 离线双模扫描页：单相机引擎同时支持 QR 解码与低照度 ML Kit OCR 桩号识别，并带手电筒与变焦控制。
class OfflineScannerScreen extends ConsumerStatefulWidget {
  const OfflineScannerScreen({super.key});

  @override
  ConsumerState<OfflineScannerScreen> createState() =>
      _OfflineScannerScreenState();
}

class _OfflineScannerScreenState extends ConsumerState<OfflineScannerScreen> {
  static const List<double> _zoomLevels = [0.0, 0.35, 0.7];
  static const List<String> _zoomLabels = ['1x', '2x', '3x'];

  late final MobileScannerController _scannerController;
  late final TextRecognizer _textRecognizer;

  ScannerMode _mode = ScannerMode.qr;
  int _zoomIndex = 0;
  bool _isConfirming = false;
  bool _isRunningOcr = false;
  DateTime _lastOcrRun = DateTime.fromMillisecondsSinceEpoch(0);
  Uint8List? _latestFrameBytes;
  String _hintText = '对准充电桩二维码，断网即可瞬间识别（反光/小码可点右上角 2x 变焦）';

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      returnImage: true,
    );
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _cycleZoom() async {
    HapticFeedback.selectionClick();
    final nextIndex = (_zoomIndex + 1) % _zoomLevels.length;
    setState(() => _zoomIndex = nextIndex);
    try {
      await _scannerController.setZoomScale(_zoomLevels[nextIndex]);
    } catch (_) {
      // 部分设备不支持平滑变焦时静默忽略
    }
  }

  void _switchMode(ScannerMode next) {
    HapticFeedback.selectionClick();
    setState(() {
      _mode = next;
      _hintText = next == ScannerMode.qr
          ? '对准充电桩二维码，断网即可瞬间识别（反光/小码可点右上角 2x 变焦）'
          : '对准设备上印刷的桩号（如 W52001715），暗光可点右上角手电筒';
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isConfirming) return;

    if (capture.image != null) {
      _latestFrameBytes = capture.image;
    }

    if (_mode == ScannerMode.qr) {
      for (final barcode in capture.barcodes) {
        final raw = barcode.rawValue?.trim();
        if (raw != null && raw.isNotEmpty) {
          _handleQrDetected(raw);
          return;
        }
      }
    } else if (_mode == ScannerMode.ocr && capture.image != null) {
      final now = DateTime.now();
      if (!_isRunningOcr &&
          now.difference(_lastOcrRun) >= const Duration(milliseconds: 900)) {
        _lastOcrRun = now;
        _runOcrOnBytes(capture.image!, manualTrigger: false);
      }
    }
  }

  Future<void> _handleQrDetected(String rawValue) async {
    if (_isConfirming) return;
    _isConfirming = true;
    HapticFeedback.mediumImpact();

    final settings = ref.read(settingsProvider);
    final extractedSn = UrlRuleEngine.extractSerialNumber(
          rawValue,
          regexPattern: settings.serialRegex,
        ) ??
        '';
    final extractedTemplate = extractedSn.isNotEmpty
        ? UrlRuleEngine.extractBaseTemplateFromUrl(rawValue, extractedSn)
        : '';

    try {
      await _scannerController.stop();
    } catch (_) {}

    await _showResultConfirmationSheet(
      detectedSerial: extractedSn,
      rawUrl: rawValue,
      suggestedBaseTemplate:
          extractedTemplate.contains('{SN}') ? extractedTemplate : null,
      sourceLabel: '离线二维码解码',
    );

    if (mounted) {
      _isConfirming = false;
      try {
        await _scannerController.start();
      } catch (_) {}
    }
  }

  Future<void> _runOcrOnBytes(
    Uint8List bytes, {
    required bool manualTrigger,
  }) async {
    if (_isRunningOcr || _isConfirming) return;
    _isRunningOcr = true;

    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        '${tempDir.path}/charge_quick_ocr_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(bytes, flush: true);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognized = await _textRecognizer.processImage(inputImage);

      final settings = ref.read(settingsProvider);
      final sn = UrlRuleEngine.extractSerialNumber(
        recognized.text,
        regexPattern: settings.serialRegex,
      );

      if (!mounted) return;
      if (sn != null && sn.isNotEmpty) {
        _isConfirming = true;
        final generatedUrl = UrlRuleEngine.previewUrl(
          AppSettings.defaultFallbackRawUrlTemplate,
          sampleSn: sn,
          samplePort: 1,
        );
        await _showResultConfirmationSheet(
          detectedSerial: sn,
          rawUrl: generatedUrl,
          suggestedBaseTemplate: null,
          sourceLabel: '离线 OCR 识别桩号',
        );
        if (mounted) {
          _isConfirming = false;
        }
      } else if (manualTrigger) {
        setState(() {
          _hintText = '未识别到符合 ${settings.serialRegex} 的编号，请靠近或开启手电筒';
        });
      }
    } catch (_) {
      if (mounted && manualTrigger) {
        setState(() {
          _hintText = 'OCR 识别暂不可用，请重试或切换到二维码模式';
        });
      }
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      _isRunningOcr = false;
    }
  }

  Future<void> _showResultConfirmationSheet({
    required String detectedSerial,
    required String rawUrl,
    required String? suggestedBaseTemplate,
    required String sourceLabel,
  }) async {
    final settings = ref.read(settingsProvider);
    final stations = ref.read(stationsProvider);
    final existing = detectedSerial.isNotEmpty
        ? stations
            .where((s) => s.serialNumber == detectedSerial.toUpperCase())
            .firstOrNull
        : null;

    final snController = TextEditingController(text: detectedSerial);
    final aliasController = TextEditingController(
      text: existing?.alias ??
          (detectedSerial.length >= 4
              ? '车库桩 ${detectedSerial.substring(detectedSerial.length - 4)}'
              : '新充电桩'),
    );
    var selectedPort = existing?.lastUsedPort ?? 1;
    var updateGlobalTemplate = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.emerald.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              sourceLabel,
                              style: const TextStyle(
                                color: AppColors.emerald,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: snController,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                        decoration: const InputDecoration(
                          labelText: '充电桩编号 (SN)',
                          hintText: '例如 W52001715',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: aliasController,
                        decoration: const InputDecoration(
                          labelText: '桩位别名',
                          hintText: '例如 B2-A区 1号桩',
                        ),
                      ),
                      const SizedBox(height: 12),
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
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: settings.defaultPortCount,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, index) {
                            final port = index + 1;
                            final selected = port == selectedPort;
                            return InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () =>
                                  setSheetState(() => selectedPort = port),
                              child: Container(
                                width: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.cyan.withValues(alpha: 0.22)
                                      : AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.cyan
                                        : AppColors.border,
                                  ),
                                ),
                                child: Text(
                                  '$port',
                                  style: TextStyle(
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
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          '原始地址：$rawUrl',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (suggestedBaseTemplate != null) ...[
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: updateGlobalTemplate,
                          contentPadding: EdgeInsets.zero,
                          activeColor: AppColors.cyan,
                          title: const Text(
                            '同步提取为支付宝直达全局模板',
                            style: TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            UrlRuleEngine.buildAlipayH5Template(
                              suggestedBaseTemplate,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          onChanged: (v) => setSheetState(
                            () => updateGlobalTemplate = v ?? false,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () async {
                                final sn = snController.text.trim().toUpperCase();
                                if (sn.isEmpty) return;
                                if (updateGlobalTemplate &&
                                    suggestedBaseTemplate != null) {
                                  await ref
                                      .read(settingsProvider.notifier)
                                      .updateGlobalTemplate(
                                        UrlRuleEngine.buildAlipayH5Template(
                                          suggestedBaseTemplate,
                                        ),
                                      );
                                }
                                await ref
                                    .read(stationsProvider.notifier)
                                    .upsertStation(
                                      id: existing?.id,
                                      alias: aliasController.text.trim(),
                                      serialNumber: sn,
                                      rawUrl: rawUrl,
                                      preserveCustomTemplateIfNull: true,
                                      lastUsedPort: selectedPort,
                                    );
                                if (!sheetContext.mounted || !mounted) return;
                                Navigator.of(sheetContext).pop();
                                Navigator.of(context).pop();
                              },
                              child: const Text('仅保存'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: AppColors.emerald,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () async {
                                final sn = snController.text.trim().toUpperCase();
                                if (sn.isEmpty) return;
                                if (updateGlobalTemplate &&
                                    suggestedBaseTemplate != null) {
                                  await ref
                                      .read(settingsProvider.notifier)
                                      .updateGlobalTemplate(
                                        UrlRuleEngine.buildAlipayH5Template(
                                          suggestedBaseTemplate,
                                        ),
                                      );
                                }
                                final saved = await ref
                                    .read(stationsProvider.notifier)
                                    .upsertStation(
                                      id: existing?.id,
                                      alias: aliasController.text.trim(),
                                      serialNumber: sn,
                                      rawUrl: rawUrl,
                                      preserveCustomTemplateIfNull: true,
                                      lastUsedPort: selectedPort,
                                    );
                                final outcome = await ref
                                    .read(launchQueueProvider.notifier)
                                    .triggerOrQueue(saved, selectedPort);
                                if (!sheetContext.mounted || !mounted) return;
                                Navigator.of(sheetContext).pop();
                                Navigator.of(context).pop(outcome);
                              },
                              child: const Text(
                                '保存并直达 / 排队',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    snController.dispose();
    aliasController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
            errorBuilder: (context, error, _) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.no_photography_rounded,
                        size: 54,
                        color: AppColors.amber,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '无法启动相机',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        error.errorDetails?.message ??
                            '请检查相机权限，或返回主页使用“输编号直达”',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          _ScannerViewfinderOverlay(mode: _mode),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _CircleIconButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            _ModeChip(
                              label: '扫码 QR',
                              selected: _mode == ScannerMode.qr,
                              onTap: () => _switchMode(ScannerMode.qr),
                            ),
                            _ModeChip(
                              label: '识编号 OCR',
                              selected: _mode == ScannerMode.ocr,
                              onTap: () => _switchMode(ScannerMode.ocr),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Material(
                        color: _zoomIndex > 0
                            ? AppColors.cyan.withValues(alpha: 0.9)
                            : Colors.black.withValues(alpha: 0.65),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _cycleZoom,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Text(
                                _zoomLabels[_zoomIndex],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: _zoomIndex > 0
                                      ? Colors.black
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<MobileScannerState>(
                        valueListenable: _scannerController,
                        builder: (context, state, _) {
                          final torchOn = state.torchState == TorchState.on;
                          return _CircleIconButton(
                            icon: torchOn
                                ? Icons.flashlight_on_rounded
                                : Icons.flashlight_off_rounded,
                            active: torchOn,
                            onTap: () => _scannerController.toggleTorch(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          _hintText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_mode == ScannerMode.ocr) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              final bytes = _latestFrameBytes;
                              if (bytes != null) {
                                _runOcrOnBytes(bytes, manualTrigger: true);
                              } else {
                                setState(() {
                                  _hintText = '相机正在准备画面，请稍候半秒再试';
                                });
                              }
                            },
                            icon: const Icon(Icons.document_scanner_rounded),
                            label: const Text(
                              '立即识别画面中的桩号',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ],
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

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? AppColors.amber.withValues(alpha: 0.9)
          : Colors.black.withValues(alpha: 0.65),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: active ? Colors.black : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.black : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ScannerViewfinderOverlay extends StatelessWidget {
  const _ScannerViewfinderOverlay({required this.mode});

  final ScannerMode mode;

  @override
  Widget build(BuildContext context) {
    final size = mode == ScannerMode.qr ? 250.0 : 290.0;
    final height = mode == ScannerMode.qr ? 250.0 : 120.0;
    return IgnorePointer(
      child: Center(
        child: Container(
          width: size,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: mode == ScannerMode.qr ? AppColors.emerald : AppColors.cyan,
              width: 2.5,
            ),
            color: Colors.transparent,
          ),
        ),
      ),
    );
  }
}
