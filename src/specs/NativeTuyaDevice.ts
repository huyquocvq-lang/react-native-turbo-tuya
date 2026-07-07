import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaDevice - điều khiển Data Points (DP) + lắng nghe trạng thái + quản lý thiết bị.
// Phát event: onDeviceStatus (online/offline + DP update) → cần addListener/removeListeners.
export type DeviceSnapshot = {
  devId: string;
  productId: string;
  dpsJson: string; // {"<dpId>": value}
  isOnline: boolean; // LAN hoặc cloud
  isLocalOnline: boolean; // chỉ LAN
  schemaJson: string; // định nghĩa kiểu DP (raw)
  dpCodesJson: string; // map dpId<->code (standard instruction set)
};

export interface Spec extends TurboModule {
  // dpsJson: chuỗi JSON {"<dpId>": <value>}; value-type là SỐ. onSuccess = "đã gửi",
  // điều khiển coi như xong khi onDeviceStatus(dpsJson) về.
  publishDps(devId: string, dpsJson: string): Promise<void>;
  getDps(devId: string): Promise<string>; // trả JSON dps hiện tại
  registerDeviceListener(devId: string): void;
  unregisterDeviceListener(devId: string): void;

  // --- Device management ---
  renameDevice(devId: string, name: string): Promise<void>;
  removeDevice(devId: string): Promise<void>;
  resetFactory(devId: string): Promise<void>;
  getWifiSignal(devId: string): Promise<number>; // RSSI (dBm)

  // --- Control nâng cao ---
  // Query 1 DP không tự báo; kết quả về qua event onDeviceStatus (onDpUpdate), KHÔNG trả trực tiếp.
  queryDp(devId: string, dpId: string): Promise<void>;
  // Đọc snapshot DP + schema + online (render UI / validate trước khi publish).
  getDeviceSnapshot(devId: string): Promise<DeviceSnapshot>;
  isDeviceOnline(devId: string): Promise<boolean>;
  isCloudConnected(): Promise<boolean>; // MQTT đã kết nối
  // mode: 'auto' | 'local' | 'internet'
  publishDpsWithMode(devId: string, dpsJson: string, mode: string): Promise<void>;
  // channels theo thứ tự ưu tiên (vd ['ble','cloud']) → map CommunicationEnum/orders
  publishDpsWithChannels(devId: string, dpsJson: string, channels: string[]): Promise<void>;
  // Publish rồi resolve khi onDpUpdate khớp (onSuccess thường chỉ = "đã gửi"). timeoutMs <=0 → mặc định.
  publishDpsAwaitAck(devId: string, dpsJson: string, timeoutMs: number): Promise<void>;
  // Low-power: gửi DP vào cache chờ thiết bị wake. dpCacheType 0=device pull,1=cloud push.
  sendCacheDps(
    devId: string,
    dpsJson: string,
    validitySec: number,
    dpCacheType: number
  ): Promise<boolean>;

  // --- BLE local control ---
  bleConnect(devId: string): Promise<void>;
  bleDisconnect(devId: string): Promise<void>;
  isBleLocalOnline(devId: string): Promise<boolean>;

  // Event emitter plumbing (bắt buộc cho NativeEventEmitter)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaDevice');
