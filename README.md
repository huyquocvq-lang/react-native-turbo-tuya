# @jimmy2k/react-native-turbo-tuya

React Native **Turbo Native Module** wrapping the Tuya Smart Life App SDK (Wi-Fi + BLE) for the ice-bath app.

Split by feature into **12 independent TurboModules** (one Codegen spec each). Legend: ✅ wired · ◑ partial / skeleton · ❌ typed TODO.

| Module | API group | Android | iOS |
|---|---|---|---|
| `TuyaCore` | init / version / destroy | ✅ | ✅ |
| `TuyaAuth` | email + 3rd-party login, profile, session *(events)* | ✅ | ✅ email-login + profile/session · ◑ code-login/3rd-party |
| `TuyaHome` | home CRUD + weather + change/status listeners *(events)* | ✅ | ✅ · ◑ weather-detail |
| `TuyaDevice` | DP control + status + device management *(events)* | ✅ | ✅ DP/status/snapshot/rename · ◑ BLE/await-ack |
| `TuyaPairing` | Wi-Fi EZ/AP, BLE, combo BLE+Wi-Fi, auto-token; advanced sub-device/gateway/QR/wired *(events)* | ✅ core · ◑ advanced | ✅ core · ◑ advanced |
| `TuyaOta` | firmware check / upgrade + auto-switch *(events)* | ✅ | ✅ check/start/cancel + progress · ◑ auto-switch |
| `TuyaScene` | scenes + automations (conditions/actions) *(events)* | ◑ skeleton | ◑ list/execute/enable/disable/delete |
| `TuyaTimer` | cloud schedules (add/update/remove/status) | ✅ · ◑ list | ◑ list/remove |
| `TuyaMessage` | push status + message center + DND | ✅ · ◑ list/by-type | ◑ push + DND on/off |
| `TuyaMember` | home members + invitation + transfer owner | ◑ | ◑ query/remove/process/transfer |
| `TuyaMatter` | Matter device pairing *(events)* | ◑ skeleton (intended-call) | ◑ skeleton (verbatim intended-call) |
| `TuyaMesh` | BLE SIG / Tuya mesh *(events)* | ◑ create/list/DP intended-call | ✅ create/list/DP/client/search/activate (best-effort) |

> **Status:** Nothing device-tested yet (building needs JDK 17 + Android SDK for Android, macOS + Xcode for iOS).
> **Android** wires the common flows (Core, Auth, Home incl. weather/listeners, Device, OTA, Pairing core + combo/auto-token, and most of Scene-adjacent Timer/Message/Member). Items marked ◑ *skeleton* (Scene, Matter, Mesh, advanced pairing) and a few bean/enum-dependent methods are **typed stubs that reject with `not_implemented` and carry the exact intended SDK call in a comment** - their underlying Tuya APIs weren't captured verbatim, so they're wired on a real-SDK machine.
> **iOS**: the full ice-bath happy path is wired - `TuyaCore.initSdk`, `TuyaAuth` (email send-code/login/register + profile/session), `TuyaHome` (CRUD + weather + listeners), `TuyaPairing` (token + Wi-Fi EZ/AP + BLE + combo + auto-token) and `TuyaDevice` (DP control + status + snapshot + rename/remove). Also partially wired on iOS: `TuyaOta` (check/start/cancel + progress), `TuyaScene` (list/execute/enable/disable/delete), `TuyaTimer` (list/remove), `TuyaMessage` (push status + DND on/off). `TuyaMember` is partially wired too (query/remove/processInvitation/transferHomeOwner). Still TODO on iOS: Auth code-login/3rd-party, advanced pairing, OTA auto-switch, Scene save/build, Timer add/update, Message list/DND-write, Member add/update + invitation, and a few Device extras (BLE/await-ack). **`TuyaMesh`**: the spec now carries `homeId` + `meshType` ('sig'|'tuya'), and **iOS is wired best-effort** (create/list/DP via `ThingSmartBleMesh`; client/search/activate via `ThingSmartSIGMeshManager` / `ThingBLEMeshManager`) per the verbatim in the Tuya iOS Matter/Mesh SDK docs - flagged ⚠️ for on-device verification of model properties. Android Mesh signatures match the spec but bodies stay intended-call (SDK import packages aren't in the docs).

**`TuyaMatter`**: documented skeleton on both platforms with verbatim intended-calls. iOS uses a *unified* `ThingSmartActivatorDiscovery` flow (≠ Android's dedicated `IMatterActivator`); full wiring is blocked on one open detail (how to construct `ThingSmartActivatorTypeMatterModel`) + Android import packages. Ice-bath devices almost certainly don't use Matter, so this is left as a documented follow-up. The event infrastructure (`RCTEventEmitter`) is in place for every event-emitting module.

## Installation

```sh
yarn add @jimmy2k/react-native-turbo-tuya
# or
npm install @jimmy2k/react-native-turbo-tuya
```

Requires React Native 0.80+ with the New Architecture (TurboModules) enabled. Building needs **JDK 17 + Android SDK** (Android) and **macOS + Xcode** (iOS).

The package contains native code, so Expo Go can't load it. In an Expo project, use a development build and add the native setup below yourself (there is no config plugin yet).

## Configuration - AppKey / AppSecret / id

> AppKey/AppSecret are loaded **natively, never from JS** (the secret must never ship in the JS bundle). Declare them once per platform, then just call `Tuya.initSdk()` - it takes no arguments.

What you need (from the Tuya IoT console):

| Item | Where it goes | Key in `keys.txt` |
|---|---|---|
| AppKey + AppSecret - **Android** | Android manifest meta-data | `ANDROID_APPKEY` / `ANDROID_SECRET` |
| AppKey + AppSecret - **iOS** (separate keys!) | iOS `Info.plist` | `IOS_APIKEY` / `IOS_SECRET` |
| `applicationId` (Android) / `bundleId` (iOS) | app identity - must **match** the package registered on the console (+ **SHA-256** for Android) | from the console |
| Data Center | must match the Cloud Project | **Central Europe** |
| Security file (binary) | Android `security-algorithm.aar` → `app/libs/` · iOS `ios_core_sdk` → next to the Podfile | console "Get SDK" |

> ⚠️ `CLOUD_CLIENT_ID` / `CLOUD_CLIENT_SECRET` in `keys.txt` are for the **backend** (Tuya Cloud OpenAPI) - **not** for this app library.
> ⚠️ Wrong AppKey/Secret, wrong `applicationId`/`bundleId`/SHA-256, or a Data Center mismatch → `illegal client` / login fails / devices not found.

### Android

1. **Maven repos** - add to your app's resolution scope (`settings.gradle` → `dependencyResolutionManagement.repositories`, or root `allprojects.repositories`):
   ```gradle
   maven { url "https://maven-other.tuya.com/repository/maven-releases/" }
   maven { url "https://maven-other.tuya.com/repository/maven-commercial-releases/" }
   ```
2. **Security file** - drop `security-algorithm.aar` into `app/libs/`, then:
   ```gradle
   dependencies { implementation fileTree(include: ['*.aar'], dir: 'libs') }
   ```
3. **Keys** - keep them out of git (use `~/.gradle/gradle.properties`, or the app's gitignored `gradle.properties`):
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

`ThingHomeSdk.init()` reads the meta-data automatically - no key is passed from JS. BLE/Wi-Fi permissions are declared in the library manifest and merge in automatically.

### iOS

1. **Security file** - unpack `ios_core_sdk` so `Build/` + `ThingSmartCryption.podspec` sit next to your Podfile.
2. **Podfile**:
   ```ruby
   source 'https://github.com/tuya/tuya-pod-specs.git'
   source 'https://cdn.cocoapods.org/'
   # inside your target:
   pod 'ThingSmartCryption', :path => './'
   ```
   (`ThingSmartHomeKit` + `ThingSmartBusinessExtensionKit` come transitively from this library's podspec.)
3. **Keys** - `Info.plist` (inject via xcconfig/CI; don't commit the real secret):
   ```xml
   <key>ThingSmartAppKey</key><string>$(THING_SMART_APPKEY)</string>
   <key>ThingSmartAppSecret</key><string>$(THING_SMART_APPSECRET)</string>
   ```
4. Add usage strings (`NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`, `NSLocationWhenInUseUsageDescription`) + a Privacy Manifest. `bundleId` must match the console.
5. Install the pods: `cd ios && pod install`.

`TuyaCore.initSdk` reads `Info.plist` → `startWithAppKey:secretKey:`.

## Usage

Everything is promise-based, apart from a few fire-and-forget calls such as `startBleScan` that return `void`. The examples use the flat `Tuya` object. The per-feature modules (`TuyaAuth`, `TuyaDevice`, …) expose the same native methods if you'd rather import by feature.

### Quick start

```ts
import { Tuya } from '@jimmy2k/react-native-turbo-tuya';

await Tuya.initSdk();                             // once at app start - keys are read natively
await Tuya.loginWithEmail('49', email, password); // '49' = country calling code, picks the data center
const home = (await Tuya.getHomeList())[0] ?? (await Tuya.createHome('Home', 0, 0, '', []));
const device = await Tuya.startWifiPairingAuto(home.homeId, 'EZ', ssid, wifiPassword, 120);
await Tuya.publishDps(device.devId, JSON.stringify({ '1': true })); // DP ids depend on the product
```

The steps below go through each part.

### 1. Start the SDK

Call `initSdk()` once when the app starts, before any other method. It rejects with `init_error` if the SDK can't start (on iOS, also when the keys are missing from `Info.plist`). The SDK keeps the session between launches, so use `isLoggedIn()` to choose between your login screen and the rest of the app:

```ts
export async function startTuya(): Promise<boolean> {
  await Tuya.initSdk();
  return Tuya.isLoggedIn();
}
```

### 2. Sign in

The country calling code you pass (`'49'`, `'1'`, `'84'`, …) decides which Tuya data center holds the account. It has to match the data center of your Tuya cloud project.

```ts
const CC = '49';

// Register: request a code (type 1), then create the account
await Tuya.sendVerifyCode(email, CC, 1);
await Tuya.registerWithEmail(CC, email, password, code);

// Log in with a password
const user = await Tuya.loginWithEmail(CC, email, password); // { uid, email, nickName, sessionId, … }

// Forgotten password: request a code (type 3), then set a new password
await Tuya.sendVerifyCode(email, CC, 3);
await Tuya.resetEmailPassword(CC, email, code, newPassword);

await Tuya.logout();
```

`sendVerifyCode` types: `1` register · `2` log in with a code · `3` reset password · `8` unregister (delete the account). Logging in with a code (`loginWithEmailCode`) works on Android only for now; iOS rejects with `ios_todo`.

**Social login** - pass the provider's token to `thirdLogin(countryCode, token, type, extraInfo)`:

| Provider | `type` | `token` | `extraInfo` |
|---|---|---|---|
| Google | `'gg'` | ID token | `'{"pubVersion":1}'` (required) |
| Apple | `'ap'` | identity token | JSON with `userIdentifier`, `email`, `nickname`, `snsNickname` when Apple provides them (first sign-in only), otherwise `''` |
| Facebook | `'fb'` | access token | `''` |

**Session expiry** - Tuya can end the session at any time (for example after a password change). The event can fire more than once, so keep the handler idempotent:

```ts
import { onSessionExpired } from '@jimmy2k/react-native-turbo-tuya';

const sub = onSessionExpired(() => goToLogin());
```

### 3. Load a home

Devices belong to a home, so every account needs at least one. Only the home's owner (`role === 2`) can pair devices.

```ts
const homes = await Tuya.getHomeList();
const home = homes[0] ?? (await Tuya.createHome('My home', 0, 0, '', [])); // name, lon, lat, geoName, rooms

const devices = await Tuya.getHomeDeviceList(home.homeId);
// [{ devId, name, productId, isOnline, iconUrl }]
```

Load the home (`getHomeDeviceList` or `getHomeDetail`) after login, on each app start and after pairing. Device methods read the SDK's local device cache, which these calls fill; without it they reject with `no_device`.

To reload when devices are added or removed elsewhere (another phone or app on the same account):

```ts
import { onHomeChange } from '@jimmy2k/react-native-turbo-tuya';

await Tuya.startHomeStatusListener(home.homeId);
const sub = onHomeChange((e) => {
  if (e.type === 'deviceAdded' || e.type === 'deviceRemoved') reloadDevices();
});
// cleanup: sub.remove(); await Tuya.stopHomeStatusListener(home.homeId);
```

### 4. Pair a device

Before you start:

- The Wi-Fi network must be 2.4 GHz. The devices can't join 5 GHz networks.
- Request the runtime permissions: location, plus `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` on Android 12+. The library's manifest declares them, but the app still has to ask the user. On iOS, the usage strings from [Configuration](#ios) must be in `Info.plist`.
- Put the device into pairing mode (see its manual).

Then pick the flow that fits the device:

| Device | Call | Notes |
|---|---|---|
| Wi-Fi | `startWifiPairingAuto(homeId, mode, ssid, password, timeoutSec)` | `mode` is `'EZ'` (LED blinks fast) or `'AP'` (LED blinks slowly; the phone has to join the device's hotspot) |
| Wi-Fi + Bluetooth (combo) | BLE scan, then `startBleWifiPairing(homeId, uuid, ssid, password, timeoutSec)` | the scan result has `isCombo: true` |
| Bluetooth only | BLE scan, then `startBlePairing(homeId, uuid, productId, address, deviceType, timeoutSec)` | the scan result has `isCombo: false` |

The auto and combo calls fetch the pairing token for you. If you use `startWifiPairing(mode, ssid, password, token, timeoutSec)` instead, call `getPairingToken(homeId)` right before each attempt: a token lasts about 10 minutes and one pairing uses it up.

**Wi-Fi**

```ts
import { Tuya, onPairingProgress } from '@jimmy2k/react-native-turbo-tuya';

const progress = onPairingProgress((e) => console.log('pairing step:', e.step));
try {
  const device = await Tuya.startWifiPairingAuto(home.homeId, 'EZ', ssid, wifiPassword, 120);
  console.log('paired', device.devId);
} finally {
  progress.remove();
}
// To cancel (e.g. the user leaves the screen): Tuya.stopWifiPairing()
```

**Bluetooth and combo**

```ts
import { Tuya, onBleScan, type BleScanEvent } from '@jimmy2k/react-native-turbo-tuya';

const found = new Map<string, BleScanEvent>();
const scan = onBleScan((d) => found.set(d.uuid, d)); // a device can show up more than once
Tuya.startBleScan(60); // seconds

// …later, once the user has picked `picked` from `found`:
Tuya.stopBleScan();
scan.remove();

const device = picked.isCombo
  ? await Tuya.startBleWifiPairing(home.homeId, picked.uuid, ssid, wifiPassword, 120)
  : await Tuya.startBlePairing(home.homeId, picked.uuid, picked.productId, picked.address, picked.deviceType, 120);
// To cancel combo pairing: Tuya.stopBleWifiPairing(picked.uuid)
```

Things to know:

- Both Bluetooth calls need a scan result for that `uuid` from the current app session, otherwise they reject with `ble_scan_required`. Stopping the scan keeps the results.
- On iOS, scan results have an empty `name`, `id` and `address`. Key your list by `uuid` and label devices by `productId`.
- `onPairingProgress` reports failures too. On iOS, the steps `device_timeout` and `device_state_error` mean the attempt failed, and `errorCode` / `errorMessage` give the reason. Android passes the SDK's step names through unchanged.
- A device you just paired may not be in the SDK cache yet. Reload the home before you control it, and retry if a call rejects with `no_device`.

### 5. Read and control a device

Devices are driven through data points (DPs). Each DP has an id (`'1'`, `'104'`, …), a code (`switch`, `temp_set`, …) and a type, all specific to the product. You can look them up under the product's function definitions in the Tuya IoT console.

```ts
const snap = await Tuya.getDeviceSnapshot(devId);
const dps = JSON.parse(snap.dpsJson); // current values by DP id, e.g. { "1": true, "104": 20 }
```

`dpsJson` looks the same on both platforms. `schemaJson` (DP types and ranges) and `dpCodesJson` (id ↔ code) come straight from each native SDK and their shapes differ between iOS and Android, so parse them defensively.

Send each value in the type of its DP:

| DP type | Value to send |
|---|---|
| bool | `true` / `false` |
| value | an integer, scaled by the DP's `scale` (with `scale: 1`, 20.5 is sent as `205`) |
| enum | one of the DP's allowed strings |
| string | a string |
| raw | a hex string |

```ts
await Tuya.publishDps(devId, JSON.stringify({ '1': true, '104': 20 }));
```

`publishDps` resolves once the command is sent, not once the device has applied it. To wait for the device, use `publishDpsAwaitAck`. It resolves when the device reports the new value and rejects with `ack_timeout` if it doesn't (`0` uses the default of 8 s):

```ts
await Tuya.publishDpsAwaitAck(devId, JSON.stringify({ '104': 20 }), 0);
```

**Live updates** - register the device, then filter the shared event stream by `devId`:

```ts
import { Tuya, onDeviceStatus } from '@jimmy2k/react-native-turbo-tuya';

export function watchDevice(devId: string, onDps: (changed: Record<string, unknown>) => void) {
  Tuya.registerDeviceListener(devId);
  const sub = onDeviceStatus((e) => {
    if (e.devId !== devId) return;               // every registered device shares this stream
    if (e.dpsJson) onDps(JSON.parse(e.dpsJson)); // only the DPs that changed
    // e.isOnline is set when the device goes online or offline
  });
  return () => {
    sub.remove();
    Tuya.unregisterDeviceListener(devId);
  };
}

// In a component:
useEffect(() => watchDevice(devId, (changed) => setDps((prev) => ({ ...prev, ...changed }))), [devId]);
```

**Managing devices**

| Call | Effect |
|---|---|
| `isDeviceOnline(devId)` | Live online state. The `isOnline` flag from `getHomeDeviceList` can be stale on iOS. |
| `renameDevice(devId, name)` | Renames the device in the Tuya cloud, so every app on the account sees the new name. |
| `removeDevice(devId)` | Removes the device from the user's home. This is not a factory reset. |
| `resetFactory(devId)` | Factory reset. Android only for now; iOS rejects with `ios_todo`. |

### 6. Schedules (cloud timers)

Timers run in the Tuya cloud and fire even when the app is closed. Use them for anything like "turn off in 30 minutes", because a JS `setTimeout` stops once iOS suspends the app.

```ts
const TASK = 'night_off'; // one task name per schedule

await Tuya.addTimer(JSON.stringify({
  taskName: TASK,
  bizId: devId,
  bizType: 'device', // or 'group'
  time: '22:30',     // HH:mm
  loops: '0111110',  // Sunday → Saturday: '0000000' = once, '1111111' = every day
  dpsJson: JSON.stringify({ '1': false }),
  status: true,      // enabled
  aliasName: 'Lights off',
}));

const timers = await Tuya.getTimerList(TASK, devId, 'device'); // [{ timerId, time, loops, status, dpsJson, aliasName }]
await Tuya.updateTimerStatus(TASK, devId, 'device', timers.map((t) => t.timerId), 'close'); // 'open' | 'close' | 'delete'
await Tuya.removeTimer(TASK, devId, 'device', []); // [] = the whole task
```

- `loops` starts on Sunday, in the same order as JS `Date.getDay()`.
- iOS ignores `timerIds` in `removeTimer` and always deletes the whole task. Give each schedule its own `taskName` and remove it with `[]`.
- Edit a timer with `updateTimer(timerId, inputJson)`. Optional input fields: `aliasName`, `appPush`, `timezone`.

### 7. Firmware updates (OTA)

```ts
import { Tuya, onOtaProgress, onOtaSuccess, onOtaFailure } from '@jimmy2k/react-native-turbo-tuya';

const updates = await Tuya.checkFirmwareUpgrade(devId);
const available = updates.filter((u) => u.upgradeStatus === 1); // 1 = update available

if (available.length > 0) {
  const subs = [
    onOtaProgress((e) => { if (e.devId === devId) setProgress(e.progress); }),
    onOtaSuccess((e) => { if (e.devId === devId) finish(); }),
    onOtaFailure((e) => { if (e.devId === devId) fail(e.code, e.message); }),
  ];
  await Tuya.startFirmwareUpgrade(devId, available.map((u) => u.type)); // [] = every type with an update
  // The outcome arrives through the events; remove `subs` after success or failure.
}
```

Cancel with `cancelFirmwareUpgrade(devId, type)`. `confirmWarningUpgrade` and the auto-upgrade switch are Android only for now.

### 8. Push notifications and the message center

After login, give Tuya the phone's push token so it can deliver device alerts. Push also has to be configured for your app in the Tuya IoT console.

```ts
import { Platform } from 'react-native';

// Android: the FCM registration token. iOS: the APNs device token.
await Tuya.registerDevice(token, Platform.OS === 'ios' ? 'apns' : 'fcm');
```

With `@react-native-firebase/messaging`, those come from `getToken()` on Android and `getAPNSToken()` on iOS.

Message center:

```ts
const page = await Tuya.getMessageList(0, 20); // { list, offset, limit, hasMore }
await Tuya.deleteMessages(page.list.map((m) => m.id));
```

### Handling errors

Every method rejects with the same shape:

| Field | Content |
|---|---|
| `code` | Tuya's error code (`'-55'`, `'1004'`, …), or one of the library codes below when the SDK gives none |
| `message` | The SDK's own description. Log it rather than replacing it with a generic string. |
| `userInfo.domain` | `'sdk'`, `'cloud'` or `'network'` |

Library codes:

| `code` | Meaning |
|---|---|
| `init_error` | The SDK couldn't start. Check the keys and the security file. |
| `no_user` | Nobody is logged in. |
| `no_home` | The home isn't in the SDK cache. Call `getHomeList()` first and check the id. |
| `no_device` | The device isn't in the SDK cache. Reload the home and retry. |
| `ble_scan_required` | Bluetooth pairing was called without a scan result for that `uuid`. |
| `ack_timeout` | `publishDpsAwaitAck` got no confirmation in time. |
| `ios_todo` / `not_implemented` | The method isn't wired on this platform yet (iOS / Android). |

Library messages are written for developers, so map these codes to your own text before showing them to users.

For Tuya's numeric codes, `TuyaErrors.classify(code, domain)` tells you what to do next:

```ts
import { Tuya, TuyaErrors } from '@jimmy2k/react-native-turbo-tuya';

try {
  await Tuya.publishDpsAwaitAck(devId, dpsJson, 0);
} catch (e: any) {
  const code = String(e?.code ?? '');
  const domain = e?.userInfo?.domain ?? 'sdk';
  if (/^-?\d+$/.test(code)) {
    const info = TuyaErrors.classify(code, domain);
    // { category, retryable, needsNewToken, needsReLogin, userMessageKey }
    if (info.needsReLogin) return goToLogin();
    if (info.retryable) return scheduleRetry();
  }
  showError(code, e?.message);
}
```

`classify` and `describe` only know Tuya's numeric codes and return `unknown` for library codes such as `no_device`. `userMessageKey` is an i18n key (`error.tuya.device_offline`, …) for your own translations.

### Events

Each `on…` helper returns a subscription; call `remove()` when you're done. Most events only flow after a start call:

| Helper | Flows after | Stop with |
|---|---|---|
| `onDeviceStatus` | `registerDeviceListener(devId)` | `unregisterDeviceListener(devId)` |
| `onPairingProgress` | a pairing call | - |
| `onBleScan` | `startBleScan(timeoutSec)` | `stopBleScan()` |
| `onHomeChange` | `startHomeChangeListener()` for homes, `startHomeStatusListener(homeId)` for the devices in one home | `stopHomeChangeListener()` / `stopHomeStatusListener(homeId)` |
| `onSessionExpired` | always on | - |
| `onOtaProgress`, `onOtaStatusChanged`, `onOtaSuccess`, `onOtaFailure` | `startFirmwareUpgrade(devId, types)` | - |

`onSceneChange`, `onMatter…` and `onMesh…` belong to the partial modules in the status table above. The raw event names are exported as `TuyaEvents`.

### Testing with Jest

Importing the package looks up the native modules straight away, so it throws under Jest. Mock it:

```js
// jest.setup.js
jest.mock('@jimmy2k/react-native-turbo-tuya', () => {
  const subscription = { remove: jest.fn() };
  return {
    Tuya: {
      initSdk: jest.fn().mockResolvedValue(true),
      isLoggedIn: jest.fn().mockResolvedValue(true),
      publishDps: jest.fn().mockResolvedValue(undefined),
      // …the other methods your code calls
    },
    onDeviceStatus: jest.fn(() => subscription),
    onSessionExpired: jest.fn(() => subscription),
    // …plus any other export you use (onBleScan, TuyaErrors, …)
  };
});
```

## Example app

A full demo lives in [`example/src/App.tsx`](example/src/App.tsx) (+ reusable UI in [`example/src/ui.tsx`](example/src/ui.tsx)): one section per module, a live event log, and `TuyaErrors`-based error classification. It walks the ice-bath happy path - **Init → Login → Create/List home → Get token → Pair (Wi-Fi/BLE) → Set target temperature** - and lets you poke every other API. Run it after a native build:

```sh
yarn        # install workspace
yarn example android   # or: yarn example ios
```

Methods marked ◑/skeleton reject with `not_implemented`; the demo surfaces that in its console (expected until they're wired on a real-SDK machine).

## Architecture

One npm package, 12 TurboModules (Codegen library `TurboTuyaSpec`):

- **TS** - one spec per module in `src/specs/NativeTuya*.ts` (Core, Auth, Home, Pairing, Device, Ota, Scene, Timer, Message, Member, Matter, Mesh); flat facade `Tuya` + per-module exports + event helpers in `src/index.tsx`; pure-JS error classifier `TuyaErrors` in `src/errors.ts`.
- **Android** - `com.jimmyvu.turbotuya.<feature>`; `TurboTuyaPackage` registers all 12. Event modules emit via `RCTDeviceEventEmitter`.
- **iOS** - `ios/<Feature>/`, each with `RCT_EXPORT_MODULE()`; event modules subclass `TuyaEventEmitter` (`RCTEventEmitter`).

Codegen constraints honoured throughout: no union types in specs (use `string`), object params passed as JSON strings, and ObjC/C++ keyword param names avoided (`operator`→`op`, `id`→`dndId`).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT

---

Made with [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
