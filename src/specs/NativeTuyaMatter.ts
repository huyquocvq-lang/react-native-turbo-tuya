import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaMatter — ghép nối thiết bị Matter (API riêng getMatterDevActivatorInstance).
// Phát event: onMatterDeviceFound (discovery), onMatterAttestation (thiết bị chưa cert), onMatterError.
// LƯU Ý: luồng STATEFUL — gọi tuần tự parseSetupCode → connectDevice → commissionDevice. Native GIỮ
//   SetupPayload/ConnectResult giữa các call (KHÔNG round-trip object native qua JS). (P3 — ít khả năng ice-bath cần.)
export type MatterSetupPayload = {
  version: number;
  vendorId: number;
  productId: number;
  setupPinCode: number;
  discriminator: number;
};

export type MatterConnectResult = {
  discoveryType: string; // 'BLE' | 'mDNS'
  ipAddress: string;
  port: number;
  thingProductId: string;
  accessType: number; // 0 = Tuya, 1 = third-party
  isThingMatter: boolean;
  nodeId: number;
  gwId: string;
};

export type MatterPairedDevice = {
  devId: string;
  name: string;
  productId: string;
};

export interface Spec extends TurboModule {
  // 1) Parse "MT:..." → payload (native giữ lại SetupPayload).
  parseSetupCode(code: string): Promise<MatterSetupPayload>;
  // 2) Connect (BLE/mDNS) dùng payload đã parse → ConnectResult (native giữ lại).
  connectDevice(homeId: number, timeoutSec: number): Promise<MatterConnectResult>;
  // 3) Commission dùng payload + connectResult đã lưu → thiết bị hoàn tất.
  commissionDevice(
    homeId: number,
    token: string,
    ssid: string,
    password: string,
    timeoutSec: number
  ): Promise<MatterPairedDevice>;

  // Auto-discovery (kết quả qua event onMatterDeviceFound).
  startDiscovery(): void;
  stopDiscovery(): void;

  // Attestation: thiết bị chưa cert → người dùng quyết định rồi tiếp tục.
  continueCommissioning(ignoreAttestationFailure: boolean): void;
  cancelActivator(): void;

  // Event emitter plumbing (bắt buộc cho NativeEventEmitter)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaMatter');
