import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 闪雀 Liquid Glass 双套配色令牌：
/// - light: 方案 5 全透明液态玻璃（浅透极光）
/// - dark:  方案 6 全透明黑曜玻璃（深透星空）
@immutable
class ZapPalette extends ThemeExtension<ZapPalette> {
  const ZapPalette({
    required this.isLight,
    required this.bgGradient,
    required this.orb1,
    required this.orb2,
    required this.orb3,
    required this.primary,
    required this.primaryFill,
    required this.onPrimary,
    required this.offline,
    required this.onOffline,
    required this.idle,
    required this.busy,
    required this.danger,
    required this.textPrimary,
    required this.textSecondary,
    required this.glassStart,
    required this.glassEnd,
    required this.glassBorder,
    required this.glassShadow,
    required this.navGlass,
    required this.navBorder,
    required this.secondaryBg,
    required this.secondaryBorder,
    required this.slotBg,
    required this.slotBusyBg,
    required this.modalSurface,
    required this.divider,
  });

  final bool isLight;
  final List<Color> bgGradient;
  final Color orb1;
  final Color orb2;
  final Color orb3;

  final Color primary;
  final Color primaryFill;
  final Color onPrimary;
  final Color offline;
  final Color onOffline;

  final Color idle;
  final Color busy;
  final Color danger;

  final Color textPrimary;
  final Color textSecondary;

  final Color glassStart;
  final Color glassEnd;
  final Color glassBorder;
  final Color glassShadow;

  final Color navGlass;
  final Color navBorder;
  final Color secondaryBg;
  final Color secondaryBorder;
  final Color slotBg;
  final Color slotBusyBg;
  final Color modalSurface;
  final Color divider;

  /// 方案 5 · 全透明液态玻璃（浅透极光）
  static const ZapPalette light = ZapPalette(
    isLight: true,
    bgGradient: [
      Color(0xFFDCE8FF),
      Color(0xFFECE6FF),
      Color(0xFFD7F3EC),
      Color(0xFFEBF2FF),
    ],
    orb1: Color(0x6638BDF8),
    orb2: Color(0x52A78BFA),
    orb3: Color(0x4734D399),
    primary: Color(0xFF007AFF),
    primaryFill: Color(0xDB007AFF),
    onPrimary: Colors.white,
    offline: Color(0xFFE58600),
    onOffline: Colors.white,
    idle: Color(0xFF10B981),
    busy: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    glassStart: Color(0x75FFFFFF),
    glassEnd: Color(0x38FFFFFF),
    glassBorder: Color(0xBAFFFFFF),
    glassShadow: Color(0x1F1F2D4D),
    navGlass: Color(0x6EFFFFFF),
    navBorder: Color(0xC2FFFFFF),
    secondaryBg: Color(0x61FFFFFF),
    secondaryBorder: Color(0xB3FFFFFF),
    slotBg: Color(0x59FFFFFF),
    slotBusyBg: Color(0x2BFFFFFF),
    modalSurface: Color(0xF2F3F7FD),
    divider: Color(0x220F172A),
  );

  /// 方案 6 · 全透明黑曜玻璃（深透星空）
  static const ZapPalette dark = ZapPalette(
    isLight: false,
    bgGradient: [
      Color(0xFF070B19),
      Color(0xFF11162B),
      Color(0xFF0B192C),
      Color(0xFF090D16),
    ],
    orb1: Color(0x5E3B82F6),
    orb2: Color(0x4A8B5CF6),
    orb3: Color(0x3B14B8A6),
    primary: Color(0xFF0A84FF),
    primaryFill: Color(0xD40A84FF),
    onPrimary: Colors.white,
    offline: Color(0xFFFF9F0A),
    onOffline: Color(0xFF09090B),
    idle: Color(0xFF34D399),
    busy: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    glassStart: Color(0x26FFFFFF),
    glassEnd: Color(0x0DFFFFFF),
    glassBorder: Color(0x3DFFFFFF),
    glassShadow: Color(0x73000000),
    navGlass: Color(0x21FFFFFF),
    navBorder: Color(0x40FFFFFF),
    secondaryBg: Color(0x1AFFFFFF),
    secondaryBorder: Color(0x36FFFFFF),
    slotBg: Color(0x17FFFFFF),
    slotBusyBg: Color(0x38000000),
    modalSurface: Color(0xF2121827),
    divider: Color(0x24FFFFFF),
  );

  @override
  ZapPalette copyWith({bool? isLight}) => this;

  @override
  ZapPalette lerp(ThemeExtension<ZapPalette>? other, double t) {
    if (other is! ZapPalette) return this;
    return t < 0.5 ? this : other;
  }
}

class AppTheme {
  const AppTheme._();

  static ZapPalette paletteOf(BuildContext context) {
    final ext = Theme.of(context).extension<ZapPalette>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.light
        ? ZapPalette.light
        : ZapPalette.dark;
  }

  static ThemeData get lightTheme => _buildTheme(Brightness.light, ZapPalette.light);
  static ThemeData get darkTheme => _buildTheme(Brightness.dark, ZapPalette.dark);

  static ThemeData _buildTheme(Brightness brightness, ZapPalette p) {
    final base = brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true)
        : ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      brightness: brightness,
      scaffoldBackgroundColor: p.bgGradient.first,
      extensions: [p],
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.primary,
        onPrimary: p.onPrimary,
        secondary: p.primary,
        onSecondary: p.onPrimary,
        tertiary: p.offline,
        onTertiary: p.onOffline,
        error: p.danger,
        onError: Colors.white,
        surface: p.modalSurface,
        onSurface: p.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.modalSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: p.glassBorder),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.modalSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      cardTheme: CardThemeData(
        color: p.glassStart,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: p.glassBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.secondaryBg,
        labelStyle: TextStyle(color: p.textSecondary),
        hintStyle: TextStyle(color: p.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.secondaryBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.secondaryBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.primary, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.modalSurface,
        contentTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.glassBorder),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: p.divider,
        thickness: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.primaryFill,
          foregroundColor: p.onPrimary,
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.secondaryBorder),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return p.primaryFill;
            return p.secondaryBg;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return p.onPrimary;
            return p.textPrimary;
          }),
          side: WidgetStatePropertyAll(
            BorderSide(color: p.secondaryBorder),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.modalSurface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.glassBorder),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? p.primary : p.textSecondary,
          );
        }),
      ),
    );
  }
}

/// 极光渐变背景：让全透明玻璃卡片产生真实的折射层次感
class ZapAuroraBackdrop extends StatelessWidget {
  const ZapAuroraBackdrop({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final overlayStyle = (p.isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          p.isLight ? Brightness.dark : Brightness.light,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: p.bgGradient,
                stops: const [0.0, 0.42, 0.80, 1.0],
              ),
            ),
          ),
          Positioned(
            top: -80,
            left: -60,
            child: _AuroraOrb(color: p.orb1, size: 280),
          ),
          Positioned(
            top: 120,
            right: -90,
            child: _AuroraOrb(color: p.orb2, size: 300),
          ),
          Positioned(
            bottom: -70,
            left: 30,
            child: _AuroraOrb(color: p.orb3, size: 280),
          ),
          child,
        ],
      ),
    );
  }
}

class _AuroraOrb extends StatelessWidget {
  const _AuroraOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// 全透明液态玻璃容器：BackdropFilter 高斯模糊 + 渐变透光 + 1px 镜面描边
class ZapGlassCard extends StatelessWidget {
  const ZapGlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.padding = EdgeInsets.zero,
    this.borderColor,
    this.blurSigma = 24,
    this.backgroundColors,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final double blurSigma;
  final List<Color>? backgroundColors;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteOf(context);
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: p.glassShadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: backgroundColors ?? [p.glassStart, p.glassEnd],
              ),
              border: Border.all(
                color: borderColor ?? p.glassBorder,
                width: 1.1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
