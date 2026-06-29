import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// NOTE: Codegen chỉ parse đúng file spec này → các object type dùng trong Spec
// phải khai báo NGAY TẠI ĐÂY (không import từ file khác). API thật neo theo
// docs/research/tuya-m1-sdk-foundation.md.

export type UserResult = {
  uid: string;
  email: string;
  nickName: string;
  sessionId: string;
};

export type HomeResult = {
  homeId: number; // long → number (an toàn < 2^53)
  name: string;
  role: number; // 2=owner, 1=admin, 0=member, -1=custom, -999=invalid
  admin: boolean;
  lon: number;
  lat: number;
  geoName: string;
};

export type DeviceResult = {
  devId: string;
  name: string;
  productId: string;
  isOnline: boolean;
  iconUrl: string;
};

export interface Spec extends TurboModule {
  // --- Init (KHÔNG tham số data center; AppKey/Secret nạp native-only) ---
  initSdk(): Promise<boolean>;
  getSdkVersion(): Promise<string>;
  destroySdk(): void;

  // --- Auth: email ---
  // type: 1=register, 2=login, 3=reset password, 8=unregister
  sendVerifyCode(
    email: string,
    countryCode: string,
    type: number
  ): Promise<void>;
  registerWithEmail(
    countryCode: string,
    email: string,
    password: string,
    code: string
  ): Promise<UserResult>;
  loginWithEmail(
    countryCode: string,
    email: string,
    password: string
  ): Promise<UserResult>;
  loginWithEmailCode(
    countryCode: string,
    email: string,
    code: string
  ): Promise<UserResult>;

  // --- Auth: third-party (Google "gg" + idToken / Apple "ap") ---
  thirdLogin(
    countryCode: string,
    token: string,
    type: string,
    extraInfo: string
  ): Promise<UserResult>;

  // --- Session ---
  isLoggedIn(): Promise<boolean>;
  getCurrentUser(): Promise<UserResult>;
  logout(): Promise<void>;

  // --- Home management (app dùng 1 nhà/user) ---
  createHome(
    name: string,
    lon: number,
    lat: number,
    geoName: string,
    rooms: string[]
  ): Promise<HomeResult>;
  getHomeList(): Promise<HomeResult[]>;
  getHomeDetail(homeId: number): Promise<HomeResult>;

  // --- Pairing: Wi-Fi (mode "EZ" | "AP"); token sống 10 phút, lấy trước mỗi lần pair ---
  getPairingToken(homeId: number): Promise<string>;
  startWifiPairing(
    mode: string,
    ssid: string,
    password: string,
    token: string,
    timeoutSec: number
  ): Promise<DeviceResult>;
  stopWifiPairing(): void;

  // --- Pairing: BLE (scan → chọn → pair); kết quả scan đẩy qua event onBleScan ---
  startBleScan(timeoutSec: number): void;
  stopBleScan(): void;
  startBlePairing(
    homeId: number,
    uuid: string,
    productId: string,
    address: string,
    deviceType: number,
    timeoutSec: number
  ): Promise<DeviceResult>;

  // --- Device control (DP) ---
  // dpsJson: chuỗi JSON {"<dpId>": <value>}; value-type là SỐ
  publishDps(devId: string, dpsJson: string): Promise<void>;
  getDps(devId: string): Promise<string>; // trả JSON dps hiện tại
  registerDeviceListener(devId: string): void;
  unregisterDeviceListener(devId: string): void;

  // --- Event emitter plumbing (bắt buộc cho NativeEventEmitter) ---
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaReactNative');
