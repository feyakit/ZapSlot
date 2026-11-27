# Google ML Kit Text Recognition: 本应用仅使用 Latin 引擎识别桩号 (如 W52001715)，
# 忽略未引入的可选语言子模块，避免 R8 Release 混淆报错。
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit 通过 ComponentDiscovery 反射实例化各 Registrar，必须完整保留。
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.mlkit.common.internal.** { *; }
