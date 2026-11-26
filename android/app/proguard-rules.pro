# Google ML Kit Text Recognition: 本应用仅使用 Latin 引擎识别桩号 (如 W52001715)，
# 忽略未引入的可选语言子模块，避免 R8 Release 混淆报错。
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
