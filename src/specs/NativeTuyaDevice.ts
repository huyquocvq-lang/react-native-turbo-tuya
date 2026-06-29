import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaDevice — điều khiển Data Points (DP) + lắng nghe trạng thái.
// Phát event: onDeviceStatus (online/offline + DP update) → cần addListener/removeListeners.
export interface Spec extends TurboModule {
  // dpsJson: chuỗi JSON {"<dpId>": <value>}; value-type là SỐ. onSuccess = "đã gửi",
  // điều khiển coi như xong khi onDeviceStatus(dpsJson) về.
  publishDps(devId: string, dpsJson: string): Promise<void>;
  getDps(devId: string): Promise<string>; // trả JSON dps hiện tại
  registerDeviceListener(devId: string): void;
  unregisterDeviceListener(devId: string): void;

  // Event emitter plumbing (bắt buộc cho NativeEventEmitter)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaDevice');
