# SETUP — tích hợp @cool-bath/tuya-react-native vào app

> Thư viện đã wrap Tuya Smart Life App SDK (TurboModule). Phần dưới là các bước app
> tiêu thụ (`example/` hoặc `apps/mobile`) phải làm — gồm **file bảo mật** (binary,
> không thể để env) + AppKey/AppSecret. Spec: `docs/research/tuya-m1-sdk-foundation.md`.

## 0. Lấy từ Tuya IoT Console (App SDK)
- **AppKey + AppSecret**
- **applicationId (Android) + SHA-256 fingerprint** + **bundleId (iOS)** đã đăng ký
- **File bảo mật:** Android `security-algorithm.aar` · iOS `ios_core_sdk.tar.gz`
- **Data Center** của App SDK = **Western Europe (EU)** — phải khớp Cloud Project.

## 1. Android (app tiêu thụ)
**a. Repo Maven của Tuya** — thêm vào nơi resolve dependency (settings.gradle
`dependencyResolutionManagement.repositories` hoặc root `allprojects.repositories`):
```gradle
maven { url "https://maven-other.tuya.com/repository/maven-releases/" }
maven { url "https://maven-other.tuya.com/repository/maven-commercial-releases/" }
```
**b. File bảo mật:** đặt `security-algorithm.aar` vào `app/libs/` và bật:
```gradle
android { ... }
dependencies { implementation fileTree(include: ['*.aar'], dir: 'libs') }
```
**c. AppKey/AppSecret** — KHÔNG hardcode trong manifest commit. Đưa qua
`gradle.properties` (gitignored, xem `gradle.properties.example`) + manifestPlaceholders:
```gradle
// app/build.gradle → android.defaultConfig
manifestPlaceholders = [
  THING_SMART_APPKEY: project.findProperty("THING_SMART_APPKEY") ?: "",
  THING_SMART_SECRET: project.findProperty("THING_SMART_SECRET") ?: "",
]
```
```xml
<!-- app/src/main/AndroidManifest.xml → trong <application> -->
<meta-data android:name="THING_SMART_APPKEY" android:value="${THING_SMART_APPKEY}" />
<meta-data android:name="THING_SMART_SECRET" android:value="${THING_SMART_SECRET}" />
```
**d. Build:** cần **JDK 17** + Android SDK. minSdk 24 (đã set ở lib). Quyền BLE/Wi-Fi
đã khai trong manifest của lib (tự merge).

## 2. iOS (app tiêu thụ)
**a. File bảo mật:** giải nén `ios_core_sdk.tar.gz` → có `Build/` + `ThingSmartCryption.podspec`,
đặt **ngang cấp Podfile** của app.
**b. Podfile** — thêm source + pod bảo mật:
```ruby
source 'https://github.com/tuya/tuya-pod-specs.git'
source 'https://cdn.cocoapods.org/'
# trong target:
pod "ThingSmartCryption", :path => "./"   # từ ios_core_sdk.tar.gz
```
(`ThingSmartHomeKit` + `ThingSmartBusinessExtensionKit` đã là dependency của podspec lib.)
**c. AppKey/AppSecret** — thêm vào **Info.plist** (inject lúc build/CI, đừng commit secret thật):
```xml
<key>ThingSmartAppKey</key><string>$(THING_SMART_APPKEY)</string>
<key>ThingSmartAppSecret</key><string>$(THING_SMART_APPSECRET)</string>
```
**d. Quyền Info.plist:** `NSBluetoothAlwaysUsageDescription`,
`NSLocalNetworkUsageDescription`, `NSLocationWhenInUseUsageDescription` + Privacy Manifest.
**e.** `pod install` (CocoaPods), build bằng Xcode.

## 3. Dùng trong JS
```ts
import { Tuya, onDeviceStatus } from '@cool-bath/tuya-react-native';
await Tuya.initSdk();                       // đọc key từ native config
await Tuya.sendVerifyCode(email, '49', 1);  // countryCode EU (vd Đức = 49)
const home = await Tuya.createHome('Home', 0, 0, '', []);
const token = await Tuya.getPairingToken(home.homeId);
await Tuya.startWifiPairing('EZ', ssid, pwd, token, 120);
const sub = onDeviceStatus((e) => console.log(e));
await Tuya.publishDps(devId, JSON.stringify({ '104': 20 }));
```

## ⚠️ Trạng thái code native (quan trọng)
- **Android:** đã implement đầy đủ theo doc nhưng **CHƯA build/verify** (máy dev thiếu
  Android SDK/JDK17 + security aar). Lần build đầu kiểm tra lại import `com.thingclips.*`
  + getter bean + chữ ký BLE. **BLE pairing (`startBlePairing`) còn TODO.**
- **iOS:** `initSdk` + `isLoggedIn` đã wire; **auth/home/pairing/BLE/DP còn TODO-reject**
  → implement bằng Tuya iOS SDK trên Xcode (đã có skeleton + selector đúng).

## ✅ Đã wire sẵn vào example (2026-06-29 — từ docs/sdk)
- **Android:** `security-algorithm-1.0.0-beta.aar` → `example/android/app/libs/`; `gradle.properties`
  có `THING_SMART_APPKEY/SECRET`; `app/build.gradle` thêm `fileTree('*.aar')` + manifestPlaceholders;
  manifest có meta-data. **DC = Central Europe.**
- **iOS:** `ios_core_sdk.tar.gz` đã giải nén → `example/ios/{Build,ThingSmartCryption.podspec}`; `Podfile`
  thêm source Tuya + `pod 'ThingSmartCryption', :path => './'` + arch-exclude; `Info.plist` có
  `ThingSmartAppKey/Secret` + usage strings.
- **Backend Cloud:** đã LIVE-verify lấy `/v1.0/token` ở `openapi.tuyaeu.com` (Central Europe) ✅.

## ⛔ CHỈ MÀY làm được (console + máy build) để chạy thật trên thiết bị
1. **Android applicationId phải TRÙNG package đã đăng ký trên Tuya console** (hiện example =
   `coolbath.tuyareactnative.example` — đổi cho khớp, hoặc đăng ký package này) + **add keystore
   SHA-256** lên console (debug.keystore). Sai → lỗi **"illegal client"** (xem README aar).
2. **iOS bundleId** trùng đăng ký console.
3. Đảm bảo **KHÔNG có file `t_s.bmp`** trong project.
4. Thêm **repo Maven Tuya** vào chỗ resolve dependency của app (settings/root) nếu build báo thiếu `thingsmart`.
5. Build bằng máy có **JDK 17 + Android SDK** (Android) · **macOS + Xcode + `pod install`** (iOS) + thiết bị thật để test pairing.
