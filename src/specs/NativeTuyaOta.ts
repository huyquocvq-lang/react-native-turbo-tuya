import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaOta - cập nhật firmware (check/start/cancel/confirm/auto-switch).
// Phát event: onOtaProgress / onOtaStatusChanged / onOtaSuccess / onOtaFailure → cần addListener/removeListeners.
export type UpgradeInfo = {
  type: number; // channel: 0=main(Wi-Fi/BT), 1=BT, 3=Zigbee, 9=MCU...
  typeDesc: string;
  currentVersion: string;
  version: string; // target
  upgradeStatus: number; // 0=none,1=has,2=updating,5=wait wake
  upgradeType: number; // 0=app prompt,2=forced,3=auto-detect
  fileSize: string;
  controlType: number; // có điều khiển được khi đang update không
  canUpgrade: boolean;
  desc: string;
};

export interface Spec extends TurboModule {
  // Trả list firmware có thể nâng (mỗi phần tử = 1 channel/type).
  checkFirmwareUpgrade(devId: string): Promise<UpgradeInfo[]>;
  // Bắt đầu nâng các type chỉ định (rỗng = tất cả type có update). Kết quả qua event, KHÔNG qua promise.
  startFirmwareUpgrade(devId: string, types: number[]): Promise<void>;
  cancelFirmwareUpgrade(devId: string, otaType: number): Promise<void>;
  // Tiếp tục khi cảnh báo (vd 5005 sóng yếu).
  confirmWarningUpgrade(devId: string, isContinue: boolean): Promise<void>;
  getAutoUpgradeSwitch(devId: string): Promise<number>;
  setAutoUpgradeSwitch(devId: string, state: number): Promise<void>;

  // Event emitter plumbing (bắt buộc cho NativeEventEmitter)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaOta');
