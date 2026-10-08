# @jimmy2k/react-native-turbo-tuya

React Native **Turbo Native Module** wrapping the Tuya Smart Life App SDK (Wi-Fi + BLE) for the ice-bath app.

Split by feature into **12 independent TurboModules** (one Codegen spec each). Legend: ✅ wired · ❌ not available in that platform's Tuya SDK (rejects with `not_implemented` on Android / `ios_todo` on iOS).

| Module | API group | Android | iOS |
|---|---|---|---|
| `TuyaCore` | init / version / destroy | ✅ | ✅ |
| `TuyaAuth` | email (password or code) + 3rd-party login, profile, session, login terminals *(events)* | ✅ · ❌ unbind / list linked 3rd-party accounts | ✅ · ❌ bind / unbind / list linked 3rd-party accounts |
| `TuyaHome` | home CRUD + weather + change/status listeners *(events)* | ✅ | ✅ |
| `TuyaDevice` | DP control + status + device management + BLE + cached DPs *(events)* | ✅ | ✅ |
| `TuyaPairing` | Wi-Fi EZ/AP, BLE, combo BLE+Wi-Fi, auto-token, sub-device, gateway, QR, wired *(events)* | ✅ | ✅ |
| `TuyaOta` | firmware check / upgrade / warnings + auto-upgrade switch *(events)* | ✅ | ✅ |
| `TuyaScene` | tap-to-run scenes + automations (conditions/actions) *(events)* | ✅ | ✅ · ❌ `enableAutomationWithTime` |
| `TuyaTimer` | cloud schedules (add/update/remove/status) | ✅ | ✅ |
| `TuyaMessage` | push status + message center + do-not-disturb | ✅ · ❌ `unregisterDevice` | ✅ |
| `TuyaMember` | home members + invitations + transfer owner | ✅ | ✅ |
| `TuyaMatter` | Matter device pairing *(events)* | ✅ | ✅ (needs the Matter pods, see [Matter](#12-matter)) |
| `TuyaMesh` | Bluetooth SIG / Tuya mesh *(events)* | ✅ | ✅ (no DP/status events) |

> **Status:** the flows used by the ice-bath app this library was built for (init, auth, homes, Wi-Fi/BLE/combo pairing, DP control, cloud timers, push and the message center) have been tested on real devices. Everything else is wired against the exact SDK versions (Tuya Android SDK 7.5.6 and the iOS pods the app ships) and compiles on both platforms, but hasn't run on hardware yet: scenes, Matter, mesh, members and invitations, do-not-disturb, sub-device/gateway/QR/wired pairing, BLE connect/disconnect and cached DPs. Treat those as beta and please report issues.

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

`sendVerifyCode` types: `1` register · `2` log in with a code · `3` reset password · `8` unregister (delete the account). To log in with a code instead of a password, call `loginWithEmailCode(CC, email, code)` after a type-`2` code.

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
| `resetFactory(devId)` | Factory reset. |
| `queryDp(devId, dpId)` | Asks the device to report one DP; the value arrives through `onDeviceStatus`. |
| `publishDpsWithChannels(devId, dpsJson, channels)` | Sends through specific channels in priority order: `'lan'`, `'cloud'` (MQTT), `'ble'`, `'sigmesh'`, `'mesh'`, … |
| `bleConnect(devId)` / `bleDisconnect(devId)` / `isBleLocalOnline(devId)` | Local Bluetooth connection. Android 12+ needs the `BLUETOOTH_CONNECT` permission. |
| `sendCacheDps(devId, dpsJson, validitySec, dpCacheType)` | Queues DPs for a sleeping low-power device (`dpCacheType` `0` = device pulls, `1` = cloud pushes). |
| `getWifiSignal(devId)` | Wi-Fi signal strength in dBm. |
| `isCloudConnected()` | Whether the SDK's MQTT connection is up. |

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

Cancel with `cancelFirmwareUpgrade(devId, type)`. When the device warns before upgrading (for example about a weak signal), answer with `confirmWarningUpgrade(devId, isContinue)`. `getAutoUpgradeSwitch(devId)` / `setAutoUpgradeSwitch(devId, state)` read and set automatic upgrades (`0` off, `1` on).

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

Do-not-disturb silences device alerts for set periods:

```ts
await Tuya.setDndStatus(true);                                                  // master switch
const id = await Tuya.addDnd('22:00', '07:00', '1111111', true, []);            // recurring, all devices
await Tuya.addOnceDnd('2026-12-24 20:00', '2026-12-25 09:00', false, [devId]);  // one-time, one device
const recurring = await Tuya.getDndList();                                      // getOnceDndList() for one-time periods
await Tuya.removeDnd(id);
```

> ⚠️ The weekday order inside DND `loops` isn't confirmed yet: Tuya's iOS helper builds it Monday-first, while the Android docs describe Sunday-first. `'1111111'` (every day) is safe either way; check single days on a device before relying on them.

### 9. Scenes and automations

A scene is either tap-to-run (`ruleGenre: 1`) or an automation (`ruleGenre: 2`) that runs when its conditions match. Build each condition and action with the `build…` helpers, then save:

```ts
await Tuya.getHomeDetail(homeId); // the builders read DP types from the cached device schema

const when = await Tuya.buildDeviceCondition(sensorId, '1', '==', 'true'); // devId, dpId, op, value
const then = await Tuya.buildDeviceAction(lightId, '1', 'true');           // devId, dpId, value

const scene = await Tuya.saveScene(homeId, JSON.stringify({
  name: 'Light on when the door opens',
  ruleGenre: 2,                           // 1 = tap-to-run, 2 = automation
  matchType: 1,                           // 1 = any condition, 2 = all conditions
  background: '',
  conditionsJson: JSON.stringify([when]), // '[]' for tap-to-run
  actionsJson: JSON.stringify([then]),
  preConditionsJson: '[]',
}));
```

- Values are always strings. `op` is `'=='`, `'<'`, `'>'`, `'<='` or `'>='` for value DPs and only `'=='` for bool and enum DPs. Value DPs take the raw integer the device reports (before `scale`).
- Other builders: `buildTimerCondition`, `buildWeatherCondition`, `buildGeofenceCondition`, `buildDelayAction`, `buildTriggerSceneAction`, `buildAutomationToggleAction`, `buildNotificationAction`. `getConditionDeviceList` / `getActionDeviceList` list the devices you can use.
- The JSON from the builders and from `getSceneDetail` is the SDK's own format and differs between iOS and Android. Treat it as opaque and don't reuse it across platforms. `getSceneDetail` output can go straight back into `modifyScene`, which only changes the keys you pass.
- Run a tap-to-run scene with `executeScene(homeId, sceneId)`; switch automations with `enableAutomation` / `disableAutomation`. `enableAutomationWithTime` is Android only.
- Weather: `getCityListByCountryCode` only covers mainland China (per Tuya's docs); elsewhere use `getCityByLocation(lat, lon)`.
- Geofence automations: iOS registers location monitoring itself when the scene is saved. On Android the app has to register the geofence, which this library doesn't expose yet.

### 10. Members and invitations

```ts
const members = await Tuya.queryMembers(homeId);
const invite = await Tuya.createInvitation(homeId); // { invitationId, code } - share the code
await Tuya.joinHomeByCode(invite.code);             // run on the invitee's account
await Tuya.addMember(homeId, account, CC, 'Alex', 0, false, false); // role 0 member · 1 admin; autoAccept false = send an invitation
```

- The role decides admin rights; both SDKs ignore the `admin` argument of `addMember`.
- `getInvitationList(homeId)` returns a JSON string of `{ invitationId, invitationCode, name, role, dealStatus, validTime }` (`validTime` in hours). Manage them with `updateInvitedMember` and `cancelInvitation`.
- Only the owner can hand the home over: `transferHomeOwner(homeId, memberId)`.

### 11. More pairing modes

| Device | Call | Needs |
|---|---|---|
| Zigbee/BLE sub-device behind a gateway | `startSubDevicePairing(gatewayDevId, timeoutSec)`; each device arrives as `onPairingProgress` step `subdevice_found` | the gateway online; no token |
| Wi-Fi gateway | `startGatewayPairing(gatewayDevId, productId, token, timeoutSec)` | phone and gateway on the same LAN, a fresh `getPairingToken` |
| Wired device | `startWiredPairing(homeId, token, timeoutSec)` | the same LAN and a fresh token; resolves with the first device found |
| Device with a QR code that is already online (e.g. 4G) | `startQrPairing(homeId, '', qrContent, timeoutSec)` | the raw QR content |

Only one gateway, QR or wired pairing runs at a time. `destroyActivator()` stops them; the pending call rejects with `pairing_cancelled`.

### 12. Matter

```ts
import { Tuya, onMatterDeviceFound, onMatterAttestation } from '@jimmy2k/react-native-turbo-tuya';

await Tuya.parseMatterSetupCode(qrOrManualCode); // QR content or the manual pairing code
const found = onMatterDeviceFound((e) => {
  const info = JSON.parse(e.dataJson ?? '{}');   // info.deviceType: 'wifi' | 'thread' | …
});
// Fires when the device fails attestation (not certified): continue only if the user accepts it
const attest = onMatterAttestation(async () => Tuya.continueMatterCommissioning(await askUserToContinue()));
await Tuya.connectMatterDevice(homeId, 120);
const token = await Tuya.getPairingToken(homeId);
const device = await Tuya.commissionMatterDevice(homeId, token, ssid, wifiPassword, 120); // Wi-Fi details only for Wi-Fi devices
found.remove();
attest.remove();
```

Android needs nothing extra. On iOS the Matter implementation isn't part of the base SDK, so without this setup every call rejects with `matter_unavailable` ([Tuya's guide](https://developer.tuya.com/en/docs/app-development/matter_device_management?id=Kcr4lk8akert0)):

1. Add `pod 'ThingSmartMatterKit'` to the app target, and create a Matter Extension target (Swift, iOS 16.1+) with `pod 'ThingSmartMatterExtensionKit'`.
2. Capabilities: **Matter Allow Setup Payload**, **App Groups** (the same group on the app and the extension) and **Background Modes → Uses Bluetooth LE accessories**.
3. `Info.plist`: `NSBonjourServices` with `_meshcop._udp`, `_matter._tcp`, `_matterc._udp`, `_matterd._udp`, plus the Bluetooth usage string.
4. Right after the app starts, call `[ThingSmartMatterActivatorConfig setMatterConfigKey:@"<your App Group>"]`; in the extension, `ThingMatterExtensionSupport.shared.setMatterConfigKey(configKey:)`.

iOS fetches its own pairing token, so the `token` argument only matters on Android.

### 13. Bluetooth mesh

```ts
import { Tuya, onMeshDeviceFound } from '@jimmy2k/react-native-turbo-tuya';

await Tuya.getHomeDetail(homeId);                       // meshes and their devices come from the home cache
const [mesh] = await Tuya.getMeshList(homeId);          // or createSigMesh(homeId, name) / createTuyaMesh(homeId, name)
Tuya.startMeshClient(homeId, mesh.meshId, mesh.type, 30); // type 'sig' or 'tuya'

const found = onMeshDeviceFound((e) => console.log(JSON.parse(e.dataJson ?? '{}'))); // { mac, name, productId, … }
Tuya.searchMeshSubDevices(homeId, mesh.meshId, mesh.type, 60);
const node = await Tuya.activateMeshSubDevice(homeId, mesh.meshId, mesh.type, mac, 120); // mac exactly as the event gave it
await Tuya.publishMeshDps(homeId, mesh.meshId, mesh.type, node.nodeId, pcc, JSON.stringify({ '1': true }));
```

- `pcc` is the device's mesh category code; Android passes it to the SDK and iOS doesn't need it.
- Tuya mesh activation covers sub-devices only. Mesh gateways pair through the Wi-Fi flows.
- iOS doesn't emit `onMeshDpUpdate` / `onMeshStatusChanged` yet.

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
| `invalid_param` / `invalid_channel` | An argument doesn't have the expected format. |
| `ble_permission_denied` | Android 12+: the app hasn't been granted `BLUETOOTH_CONNECT`. |
| `pairing_cancelled` | A newer gateway/QR/wired pairing call or `destroyActivator()` replaced this one. |
| `matter_unavailable` | iOS: the Matter pods aren't installed (see [Matter](#12-matter)). |
| `ios_todo` / `not_implemented` | The platform's Tuya SDK has no API for this method (see the status table). The message says why. |

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
| `onSceneChange` | `registerSceneChangeListener()`. Android reports add/update/delete/enable/disable; iOS only enable/disable | `unregisterSceneChangeListener()` |
| `onMatterDeviceFound`, `onMatterAttestation`, `onMatterError` | `startDiscovery()` / `connectDevice(...)` | `stopDiscovery()` / `cancelActivator()` |
| `onMeshDeviceFound` | `searchSubDevices(...)` | `stopMeshClient(...)` |
| `onMeshDpUpdate`, `onMeshStatusChanged` | Android only, while `startMeshClient(...)` runs | `stopMeshClient(...)` |

The raw event names are exported as `TuyaEvents`.

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

The few methods a platform's SDK doesn't support reject with `not_implemented` / `ios_todo`; the demo shows that in its console.

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
