# @jimmy-vu/react-native-turbo-tuya

React Native **Turbo Native Module** wrapping the Tuya Smart Life App SDK (Wi-Fi + BLE) for the ice-bath app.

Split by feature into **12 independent TurboModules** (one Codegen spec each). Legend: ✅ wired · ◑ partial / skeleton · ❌ typed TODO.

| Module | API group | Android | iOS |
|---|---|---|---|
| `TuyaCore` | init / version / destroy | ✅ | ✅ |
| `TuyaAuth` | email + 3rd-party login, profile, session *(events)* | ✅ | ◑ profile/session; email-login TODO |
| `TuyaHome` | home CRUD + weather + change/status listeners *(events)* | ✅ | ❌ |
| `TuyaDevice` | DP control + status + device management *(events)* | ✅ | ❌ |
| `TuyaPairing` | Wi-Fi EZ/AP, BLE, combo BLE+Wi-Fi, auto-token; advanced sub-device/gateway/QR/wired *(events)* | ✅ core · ◑ advanced | ❌ |
| `TuyaOta` | firmware check / upgrade + auto-switch *(events)* | ✅ | ❌ |
| `TuyaScene` | scenes + automations (conditions/actions) *(events)* | ◑ skeleton | ❌ |
| `TuyaTimer` | cloud schedules (add/update/remove/status) | ✅ · ◑ list | ❌ |
| `TuyaMessage` | push status + message center + DND | ✅ · ◑ list/by-type | ❌ |
| `TuyaMember` | home members + invitation + transfer owner | ◑ | ❌ |
| `TuyaMatter` | Matter device pairing *(events)* | ◑ skeleton | ❌ |
| `TuyaMesh` | BLE SIG / Tuya mesh *(events)* | ◑ skeleton | ❌ |

> **Status:** Nothing device-tested yet (building needs JDK 17 + Android SDK for Android, macOS + Xcode for iOS).
> **Android** wires the common flows (Core, Auth, Home incl. weather/listeners, Device, OTA, Pairing core + combo/auto-token, and most of Scene-adjacent Timer/Message/Member). Items marked ◑ *skeleton* (Scene, Matter, Mesh, advanced pairing) and a few bean/enum-dependent methods are **typed stubs that reject with `not_implemented` and carry the exact intended SDK call in a comment** — their underlying Tuya APIs weren't captured verbatim, so they're wired on a real-SDK machine.
> **iOS** has `TuyaCore.initSdk` + `TuyaAuth` profile/session wired; the rest is a typed skeleton (TODO) to finish in Xcode. The event infrastructure (`RCTEventEmitter`) is in place for every event-emitting module.

## Installation

```sh
yarn add @jimmy-vu/react-native-turbo-tuya
```

Requires React Native 0.80+ with the New Architecture (TurboModules) enabled. Building needs **JDK 17 + Android SDK** (Android) and **macOS + Xcode** (iOS).

## Configuration — AppKey / AppSecret / id

> AppKey/AppSecret are loaded **natively, never from JS** (the secret must never ship in the JS bundle). Declare them once per platform, then just call `Tuya.initSdk()` — it takes no arguments.

What you need (from the Tuya IoT console; in this repo they live in `docs/sdk/keys.txt`):

| Item | Where it goes | Key in `keys.txt` |
|---|---|---|
| AppKey + AppSecret — **Android** | Android manifest meta-data | `ANDROID_APPKEY` / `ANDROID_SECRET` |
| AppKey + AppSecret — **iOS** (separate keys!) | iOS `Info.plist` | `IOS_APIKEY` / `IOS_SECRET` |
| `applicationId` (Android) / `bundleId` (iOS) | app identity — must **match** the package registered on the console (+ **SHA-256** for Android) | from the console |
| Data Center | must match the Cloud Project | **Central Europe** |
| Security file (binary) | Android `security-algorithm.aar` → `app/libs/` · iOS `ios_core_sdk` → next to the Podfile | console "Get SDK" |

> ⚠️ `CLOUD_CLIENT_ID` / `CLOUD_CLIENT_SECRET` in `keys.txt` are for the **backend** (Tuya Cloud OpenAPI) — **not** for this app library.
> ⚠️ Wrong AppKey/Secret, wrong `applicationId`/`bundleId`/SHA-256, or a Data Center mismatch → `illegal client` / login fails / devices not found.

### Android

1. **Maven repos** — add to your app's resolution scope (`settings.gradle` → `dependencyResolutionManagement.repositories`, or root `allprojects.repositories`):
   ```gradle
   maven { url "https://maven-other.tuya.com/repository/maven-releases/" }
   maven { url "https://maven-other.tuya.com/repository/maven-commercial-releases/" }
   ```
2. **Security file** — drop `security-algorithm.aar` into `app/libs/`, then:
   ```gradle
   dependencies { implementation fileTree(include: ['*.aar'], dir: 'libs') }
   ```
3. **Keys** — keep them out of git (use `~/.gradle/gradle.properties`, or the app's gitignored `gradle.properties`):
   ```properties
   THING_SMART_APPKEY=<ANDROID_APPKEY>
   THING_SMART_SECRET=<ANDROID_SECRET>
   ```
   Inject into the manifest:
   ```gradle
   // app/build.gradle → android.defaultConfig
   manifestPlaceholders = [
     THING_SMART_APPKEY: (project.findProperty("THING_SMART_APPKEY") ?: ""),
     THING_SMART_SECRET: (project.findProperty("THING_SMART_SECRET") ?: ""),
   ]
   ```
   ```xml
   <!-- AndroidManifest.xml → inside <application> -->
   <meta-data android:name="THING_SMART_APPKEY" android:value="${THING_SMART_APPKEY}" />
   <meta-data android:name="THING_SMART_SECRET" android:value="${THING_SMART_SECRET}" />
   ```
4. Set `applicationId` to the console-registered package and add the keystore **SHA-256** on the console.

`ThingHomeSdk.init()` reads the meta-data automatically — no key is passed from JS. BLE/Wi-Fi permissions are declared in the library manifest and merge in automatically.

### iOS

1. **Security file** — unpack `ios_core_sdk` so `Build/` + `ThingSmartCryption.podspec` sit next to your Podfile.
2. **Podfile**:
   ```ruby
   source 'https://github.com/tuya/tuya-pod-specs.git'
   source 'https://cdn.cocoapods.org/'
   # inside your target:
   pod 'ThingSmartCryption', :path => './'
   ```
   (`ThingSmartHomeKit` + `ThingSmartBusinessExtensionKit` come transitively from this library's podspec.)
3. **Keys** — `Info.plist` (inject via xcconfig/CI; don't commit the real secret):
   ```xml
   <key>ThingSmartAppKey</key><string>$(THING_SMART_APPKEY)</string>
   <key>ThingSmartAppSecret</key><string>$(THING_SMART_APPSECRET)</string>
   ```
4. Add usage strings (`NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `NSLocationWhenInUseUsageDescription`) + a Privacy Manifest. `bundleId` must match the console.

`TuyaCore.initSdk` reads `Info.plist` → `startWithAppKey:secretKey:`.

## Usage

```ts
import { Tuya, onDeviceStatus } from '@jimmy-vu/react-native-turbo-tuya';

await Tuya.initSdk();                          // reads native config; no key from JS
await Tuya.sendVerifyCode(email, '49', 1);     // EU country code (e.g. Germany = 49)
const home = await Tuya.createHome('Home', 0, 0, '', []);
const token = await Tuya.getPairingToken(home.homeId); // 10-min token; fetch before each pair
await Tuya.startWifiPairing('EZ', ssid, pwd, token, 120);

const sub = onDeviceStatus((e) => console.log(e));
await Tuya.publishDps(devId, JSON.stringify({ '104': 20 })); // DP values are numbers
sub.remove();
```

Prefer per-feature imports? `import { TuyaAuth, TuyaDevice } from '@jimmy-vu/react-native-turbo-tuya'`.

## Example app

A full demo lives in [`example/src/App.tsx`](example/src/App.tsx) (+ reusable UI in [`example/src/ui.tsx`](example/src/ui.tsx)): one section per module, a live event log, and `TuyaErrors`-based error classification. It walks the ice-bath happy path — **Init → Login → Create/List home → Get token → Pair (Wi-Fi/BLE) → Set target temperature** — and lets you poke every other API. Run it after a native build:

```sh
yarn        # install workspace
yarn example android   # or: yarn example ios
```

Methods marked ◑/skeleton reject with `not_implemented`; the demo surfaces that in its console (expected until they're wired on a real-SDK machine).

## Events

Event-emitting modules expose `onXxx(listener) → { remove() }` helpers (built on `NativeEventEmitter`), plus the `TuyaEvents` name constants:

```ts
import { onDeviceStatus, onPairingProgress, onBleScan, onSessionExpired,
         onOtaProgress, onOtaStatusChanged, onOtaSuccess, onOtaFailure,
         onSceneChange, onHomeChange,
         onMatterDeviceFound, onMatterAttestation, onMatterError,
         onMeshDeviceFound, onMeshDpUpdate, onMeshStatusChanged } from '@jimmy-vu/react-native-turbo-tuya';
```

## Architecture

One npm package, 12 TurboModules (Codegen library `TurboTuyaSpec`):

- **TS** — one spec per module in `src/specs/NativeTuya*.ts` (Core, Auth, Home, Pairing, Device, Ota, Scene, Timer, Message, Member, Matter, Mesh); flat facade `Tuya` + per-module exports + event helpers in `src/index.tsx`; pure-JS error classifier `TuyaErrors` in `src/errors.ts`.
- **Android** — `com.jimmyvu.turbotuya.<feature>`; `TurboTuyaPackage` registers all 12. Event modules emit via `RCTDeviceEventEmitter`.
- **iOS** — `ios/<Feature>/`, each with `RCT_EXPORT_MODULE()`; event modules subclass `TuyaEventEmitter` (`RCTEventEmitter`).

Codegen constraints honoured throughout: no union types in specs (use `string`), object params passed as JSON strings, and ObjC/C++ keyword param names avoided (`operator`→`op`, `id`→`dndId`).

Notes: the account linking the SDK must be the **Owner** of the Home (`role == 2`). A pairing token lives ~10 minutes and dies after one device pairs — fetch it right before each pairing (or use `startWifiPairingAuto` / `startBleWifiPairing` which fetch it for you). Only 2.4 GHz Wi-Fi is supported.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
