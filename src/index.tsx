import { NativeEventEmitter } from 'react-native';
import TuyaCore from './specs/NativeTuyaCore';
import TuyaAuth from './specs/NativeTuyaAuth';
import TuyaHome from './specs/NativeTuyaHome';
import TuyaPairing from './specs/NativeTuyaPairing';
import TuyaDevice from './specs/NativeTuyaDevice';

// --- Re-export type kết quả (khai báo inline trong từng spec do ràng buộc codegen) ---
export type { UserResult } from './specs/NativeTuyaAuth';
export type { HomeResult } from './specs/NativeTuyaHome';
export type { DeviceResult } from './specs/NativeTuyaPairing';

// --- Sub-module theo tính năng (truy cập trực tiếp nếu muốn) ---
export { TuyaCore, TuyaAuth, TuyaHome, TuyaPairing, TuyaDevice };

// --- Phân loại lỗi (JS-only) + chuẩn shape lỗi { code, message, domain } ---
export { TuyaErrors } from './errors';
export type {
  TuyaError,
  TuyaErrorInfo,
  TuyaErrorCategory,
  TuyaErrorDomain,
} from './errors';

// --- Event payloads (JS-only; không qua codegen) ---
export type DeviceStatusEvent = {
  devId: string;
  isOnline?: boolean;
  dpsJson?: string; // JSON các DP vừa đổi
};
export type PairingProgressEvent = {
  step: string;
  dataJson?: string;
};
export type BleScanEvent = {
  id: string;
  name: string;
  productId: string;
  uuid: string;
  mac: string;
  address: string;
  deviceType: number;
};

export type Subscription = { remove(): void };

/**
 * Facade phẳng gộp 5 TurboModule — giữ tương thích `Tuya.<method>()`.
 * Mỗi tính năng là 1 native module riêng (Core/Auth/Home/Pairing/Device);
 * có thể import thẳng sub-module ở trên nếu muốn tách rõ theo feature.
 */
export const Tuya = {
  // Core
  initSdk: TuyaCore.initSdk,
  getSdkVersion: TuyaCore.getSdkVersion,
  destroySdk: TuyaCore.destroySdk,
  // Auth
  sendVerifyCode: TuyaAuth.sendVerifyCode,
  registerWithEmail: TuyaAuth.registerWithEmail,
  loginWithEmail: TuyaAuth.loginWithEmail,
  loginWithEmailCode: TuyaAuth.loginWithEmailCode,
  thirdLogin: TuyaAuth.thirdLogin,
  isLoggedIn: TuyaAuth.isLoggedIn,
  getCurrentUser: TuyaAuth.getCurrentUser,
  logout: TuyaAuth.logout,
  // Home
  createHome: TuyaHome.createHome,
  getHomeList: TuyaHome.getHomeList,
  getHomeDetail: TuyaHome.getHomeDetail,
  // Pairing
  getPairingToken: TuyaPairing.getPairingToken,
  startWifiPairing: TuyaPairing.startWifiPairing,
  stopWifiPairing: TuyaPairing.stopWifiPairing,
  startBleScan: TuyaPairing.startBleScan,
  stopBleScan: TuyaPairing.stopBleScan,
  startBlePairing: TuyaPairing.startBlePairing,
  // Device
  publishDps: TuyaDevice.publishDps,
  getDps: TuyaDevice.getDps,
  registerDeviceListener: TuyaDevice.registerDeviceListener,
  unregisterDeviceListener: TuyaDevice.unregisterDeviceListener,
};

export default Tuya;

export const TuyaEvents = {
  DEVICE_STATUS: 'onDeviceStatus',
  PAIRING_PROGRESS: 'onPairingProgress',
  BLE_SCAN: 'onBleScan',
} as const;

// Device-status đi qua module TuyaDevice; pairing/BLE-scan đi qua module TuyaPairing.
// (Hai module đều implement addListener/removeListeners → hợp lệ làm nguồn NativeEventEmitter.)
const deviceEmitter = new NativeEventEmitter(TuyaDevice as never);
const pairingEmitter = new NativeEventEmitter(TuyaPairing as never);

export function onDeviceStatus(
  listener: (event: DeviceStatusEvent) => void
): Subscription {
  return deviceEmitter.addListener(TuyaEvents.DEVICE_STATUS, (event: Object) =>
    listener(event as unknown as DeviceStatusEvent)
  );
}

export function onPairingProgress(
  listener: (event: PairingProgressEvent) => void
): Subscription {
  return pairingEmitter.addListener(TuyaEvents.PAIRING_PROGRESS, (event: Object) =>
    listener(event as unknown as PairingProgressEvent)
  );
}

export function onBleScan(
  listener: (event: BleScanEvent) => void
): Subscription {
  return pairingEmitter.addListener(TuyaEvents.BLE_SCAN, (event: Object) =>
    listener(event as unknown as BleScanEvent)
  );
}
