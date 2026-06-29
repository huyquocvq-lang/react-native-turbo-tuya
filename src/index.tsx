import { NativeEventEmitter } from 'react-native';
import TuyaSpec from './NativeTuyaReactNative';
import type {
  UserResult,
  HomeResult,
  DeviceResult,
} from './NativeTuyaReactNative';

export type { UserResult, HomeResult, DeviceResult };

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

/** Bề mặt API native (TurboModule). Native impl ở B5–B9. */
export const Tuya = TuyaSpec;
export default TuyaSpec;

export const TuyaEvents = {
  DEVICE_STATUS: 'onDeviceStatus',
  PAIRING_PROGRESS: 'onPairingProgress',
  BLE_SCAN: 'onBleScan',
} as const;

// TuyaSpec implement addListener/removeListeners → hợp lệ làm nguồn cho NativeEventEmitter.
const emitter = new NativeEventEmitter(TuyaSpec as never);

export function onDeviceStatus(
  listener: (event: DeviceStatusEvent) => void
): Subscription {
  return emitter.addListener(TuyaEvents.DEVICE_STATUS, (event: Object) =>
    listener(event as unknown as DeviceStatusEvent)
  );
}

export function onPairingProgress(
  listener: (event: PairingProgressEvent) => void
): Subscription {
  return emitter.addListener(TuyaEvents.PAIRING_PROGRESS, (event: Object) =>
    listener(event as unknown as PairingProgressEvent)
  );
}

export function onBleScan(
  listener: (event: BleScanEvent) => void
): Subscription {
  return emitter.addListener(TuyaEvents.BLE_SCAN, (event: Object) =>
    listener(event as unknown as BleScanEvent)
  );
}
