# 快充直达 (ChargeQuick)

一款零后端、极速冷启动、专为**地下车库无信号扫码充电**与**跳过小程序开屏广告**打造的 Flutter 跨平台工具应用（iOS / Android）。

## 核心特性

1. **地库离线扫桩 & 排队直达**
   - 插好充电枪后，直接点选常用桩插座口（`1`–`10`）、使用离线双模扫描器（二维码 + 低光 ML Kit OCR 识桩号 + 手电筒）、或用大键盘输入 4 位尾号（如 `1715` 自动补全 `W52001715`）。
   - 无网络时自动将任务持久化到本地队列；坐电梯上楼网络恢复瞬间：
     - 推送高优先级系统通知（点击通知即可直接跳转充电页面）；
     - 若 App 在前台且开启了自动跳转，立即触发 `launchUrl` 拉起外部应用。

2. **国内网络真实连通性探测**
   - 使用 `connectivity_plus` + `internet_connection_checker_plus`（配置 `connect.rom.miui.com/generate_204`、`wifi.vivo.com.cn/generate_204`、`res.wx.qq.com` 等国内毫秒级探测点），避免海外探针超时和地库假 Wi-Fi 误判。

3. **三层优先级 URL 规则引擎（跳过开屏广告）**
   - **第一优先级：单桩独立覆盖链接**（适合填写微信固定 `weixin://dl/business/?t=...` 短链或特殊桩链接）。
   - **第二优先级：全局模板**（支持 `{SN}` 与 `{PORT}` 占位符，适合支付宝小程序直达 `alipays://platformapi/startapp?...` 或自定义 HTTPS 模板）。
   - **第三优先级：原始扫码链接**。

## 本地运行与打包

> 当前工程已包含完整的 `lib/`、`test/`、`pubspec.yaml`、`AndroidManifest.xml` 与 `Info.plist`。请在已安装 Flutter SDK 的本机执行以下命令：

```bash
# 1. 进入项目目录
cd /home/ubuntu/.gemini/antigravity/scratch/charge_quick

# 2. 若需补齐本机 Android/iOS 原生工程壳文件（保留已有 Manifest 与 Info.plist）
flutter create . --platforms=android,ios

# 3. 安装依赖并运行单元测试
flutter pub get
flutter test

# 4. 真机运行（建议用真机测试相机、手电筒与微信/支付宝 Scheme 跳转）
flutter run --release
```

### Android 注意事项
- `android/app/src/main/AndroidManifest.xml` 已配置 `CAMERA`、`INTERNET`、`ACCESS_NETWORK_STATE`、`POST_NOTIFICATIONS` 权限以及 `<queries>` 中的 `weixin` / `alipays` / `https` / `http` Scheme。
- 若使用 Android Gradle 构建，请确保 `minSdkVersion >= 21`（`mobile_scanner` 与 `google_mlkit_text_recognition` 要求）且 `compileSdk >= 34`。

### iOS 注意事项
- `ios/Runner/Info.plist` 已配置 `NSCameraUsageDescription` 与 `LSApplicationQueriesSchemes`（`weixin`、`alipays`）。
- 运行 `cd ios && pod install` 前请确认 `Podfile` 中的 iOS Deployment Target 不低于 `15.5`（Google ML Kit 依赖要求）。
