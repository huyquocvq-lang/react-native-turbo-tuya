import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaPairing — ghép nối thiết bị Wi-Fi (EZ/AP) + BLE.
// Phát event: onPairingProgress, onBleScan (qua NativeEventEmitter) → cần addListener/removeListeners.
export type DeviceResult = {
  devId: string;
  name: string;
  productId: string;
  isOnline: boolean;
  iconUrl: string;
};

export interface Spec extends TurboModule {
  // Token sống 10 phút + chết sau 1 lần pair → lấy ngay trước mỗi lần pairing
  getPairingToken(homeId: number): Promise<string>;

  // Wi-Fi: mode "EZ" | "AP" (chỉ 2.4GHz)
  startWifiPairing(
    mode: string,
    ssid: string,
    password: string,
    token: string,
    timeoutSec: number
  ): Promise<DeviceResult>;
  stopWifiPairing(): void;

  // BLE: scan (đẩy kết quả qua onBleScan) → chọn theo uuid → pair
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

  // Event emitter plumbing (bắt buộc cho NativeEventEmitter)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaPairing');
