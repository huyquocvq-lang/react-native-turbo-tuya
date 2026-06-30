import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaPairing — ghép nối thiết bị Wi-Fi (EZ/AP) + BLE + combo BLE+Wi-Fi (dual-mode).
// Phát event: onPairingProgress (kể cả combo stage), onBleScan (qua NativeEventEmitter) → cần addListener/removeListeners.
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

  // --- Combo / dual-mode (BLE + Wi-Fi) ---
  // Cần đã startBleScan để có uuid trong cache scan. Token tự lấy bên trong (auto-token).
  // Stage trung gian báo qua event onPairingProgress (step='combo_stage').
  startBleWifiPairing(
    homeId: number,
    uuid: string,
    ssid: string,
    password: string,
    timeoutSec: number
  ): Promise<DeviceResult>;
  stopBleWifiPairing(uuid: string): void;

  // --- Auto-token Wi-Fi (EZ/AP) ---
  // Như startWifiPairing nhưng tự getActivatorToken(homeId) — khỏi quản lý token thủ công.
  startWifiPairingAuto(
    homeId: number,
    mode: string,
    ssid: string,
    password: string,
    timeoutSec: number
  ): Promise<DeviceResult>;

  // --- P3: pairing nâng cao (unified ActivatorService Android / ThingSmartActivator iOS) ---
  // Sub-device (Zigbee/BLE) qua gateway: gateway phải online cloud; KHÔNG cần token.
  // Mỗi sub-device tìm thấy báo qua onPairingProgress(step='subdevice_found', dataJson=devId).
  startSubDevicePairing(gatewayDevId: string, timeoutSec: number): void;
  stopSubDevicePairing(gatewayDevId: string): void;
  // Pair chính gateway Wi-Fi (cần token + productId).
  startGatewayPairing(
    gatewayDevId: string,
    productId: string,
    token: string,
    timeoutSec: number
  ): Promise<DeviceResult>;
  // QR IN thiết bị (thiết bị đã online internet): Android QRScanActivator; iOS parseQRCode+getTokenWithUUID.
  startQrPairing(
    homeId: number,
    assetId: string,
    code: string,
    timeoutSec: number
  ): Promise<DeviceResult>;
  // Wired (thiết bị nối dây): phát hiện rồi activate bằng token.
  startWiredPairing(
    homeId: number,
    token: string,
    timeoutSec: number
  ): Promise<DeviceResult>;
  // Giải phóng activator nâng cao khi rời màn (activator.destroy()/onDestroy()).
  destroyActivator(): void;

  // Event emitter plumbing (bắt buộc cho NativeEventEmitter)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaPairing');
