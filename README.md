<p align="center">
  <img src="assets/images/logo.png" width="112" height="112" alt="闪雀 ZapSlot Logo" style="border-radius: 24px;" />
</p>

# 闪雀 (ZapSlot)

一款零后端、极速冷启动、专为**地下车库无信号扫码充电**与**跳过小程序开屏广告**打造的 Flutter 跨平台工具应用（iOS / Android）。

## 核心特性

1. **地库离线扫桩 & 排队直达**
   - 插好充电枪后，直接点选常用桩插座口（`1`–`10`）、使用离线双模扫描器（二维码 + 低光 ML Kit OCR 识桩号 + 手电筒 + `1x/2x/3x` 变焦）、或用大键盘输入 4 位尾号（如 `1715` 自动补全 `W52001715` 并自动同步上次插座号）。
   - 无网络时自动将任务持久化到本地队列；坐电梯上楼网络恢复瞬间：
     - 推送高优先级系统通知（点击通知即可直接跳转充电页面）；
     - 若 App 在前台且开启了自动跳转，立即触发 `launchUrl` 拉起外部应用。

2. **国内网络真实连通性探测**
   - 使用 `connectivity_plus` + `internet_connection_checker_plus`（配置 `connect.rom.miui.com/generate_204`、`wifi.vivo.com.cn/generate_204`、`res.wx.qq.com` 等国内毫秒级探测点），避免海外探针超时和地库假 Wi-Fi 误判。

3. **三层优先级 URL 规则引擎（跳过开屏广告）**
   - **第一优先级：单桩独立覆盖链接**（适合填写微信固定 `weixin://dl/business/?t=...` 短链或特殊桩链接）。
   - **第二优先级：全局模板**（支持 `{SN}`、`{PORT}`、`{RAW_URL}`、`{RAW_URL_ENCODED}` 占位符，内置微云充支付宝内置浏览器直达 `alipays://platformapi/startapp?appId=20000067&url=...` 与通用二维码封装模板）。
   - **第三优先级：原始扫码链接**。

## 本地运行与打包

> 当前工程已包含完整的 Flutter 源码（`lib/`、`test/`）以及预配置好的 Android / iOS 原生工程（`android/`、`ios/`），无需再执行 `flutter create`。

```bash
# 1. 进入项目目录
cd ZapSlot

# 2. 安装依赖并运行单元测试与组件测试
flutter pub get
flutter test

# 3. 真机运行（建议用真机测试相机、手电筒、变焦与微信/支付宝 Scheme 跳转）
flutter run --release

# 4. 打包 Android APK
flutter build apk --release
```

### Android 配置说明
- `android/app/src/main/AndroidManifest.xml` 已配置 `CAMERA`、`INTERNET`、`ACCESS_NETWORK_STATE`、`POST_NOTIFICATIONS`、`VIBRATE` 权限以及 `<queries>` 中的 `weixin` / `alipays` / `https` / `http` Scheme。
- `android/app/build.gradle.kts` 已启用 `org.jetbrains.kotlin.android`、`minSdk >= 21`、`multiDexEnabled = true`、`coreLibraryDesugaring`，并支持通过 `android/key.properties`（参见 `android/key.properties.example`）进行正式 Release 签名（未配置时自动回退至 debug 签名便于本地/CI 验证）。
- 离线排队时自动通过 `workmanager` 注册**联网约束一次性任务（OneOffTask）+ 15 分钟周期兜底任务（PeriodicTask）**，即使 App 被 MIUI/ColorOS 杀后台，出电梯联网后仍可唤醒并推送高优先级直达通知（极端省电策略下最晚由 15 分钟周期任务兜底）。

### iOS 配置说明
- `ios/Runner/AppDelegate.swift` 已配置 `UNUserNotificationCenter.current().delegate = self` 以支持前台通知展示。
- `ios/Runner/Info.plist` 已配置 `NSCameraUsageDescription`、`LSApplicationQueriesSchemes`（`weixin`、`alipays`）、`UIBackgroundModes`（`fetch`、`processing`）与 `BGTaskSchedulerPermittedIdentifiers`（`com.feyakit.chargeQuick.networkRecovery`）。
- `ios/Runner.xcodeproj/project.pbxproj` 已将 iOS Deployment Target 设为 `15.5`（Google ML Kit 依赖要求），在 macOS 上执行 `cd ios && pod install` 即可构建。
