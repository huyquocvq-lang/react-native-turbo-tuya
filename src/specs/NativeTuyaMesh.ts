import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaMesh — Bluetooth Mesh (SIG + Tuya private). Phát event:
//   onMeshDeviceFound (search), onMeshDpUpdate (DP), onMeshStatusChanged (online/offline node).
// LƯU Ý: STATEFUL — phải startMeshClient (connect proxy) trước khi search/control. Native GIỮ mesh client +
//   device instance. (P3 — note bluetooth: chỉ làm nếu thực sự có thiết bị mesh; ice-bath nhiều khả năng KHÔNG cần.)
export type MeshInfo = {
  meshId: string;
  name: string;
  type: string; // 'sig' | 'tuya'
};

export type MeshSubDevice = {
  devId: string;
  name: string;
  productId: string;
  nodeId: string;
};

export interface Spec extends TurboModule {
  // --- Tạo / liệt kê mesh (1 lần/home) ---
  createSigMesh(homeId: number, name: string): Promise<string>; // -> meshId
  createTuyaMesh(homeId: number, name: string): Promise<string>; // -> meshId
  getMeshList(homeId: number): Promise<MeshInfo[]>;

  // --- Client lifecycle (connect proxy) ---
  // meshType: 'sig' | 'tuya' — chọn SIG (ThingSmartSIGMeshManager) vs Tuya (ThingBLEMeshManager) manager.
  // homeId: bắt buộc để dựng mesh instance (iOS bleMeshWithMeshId:homeId:) + SIG manager.
  startMeshClient(
    homeId: number,
    meshId: string,
    meshType: string,
    searchTimeSec: number
  ): void;
  stopMeshClient(homeId: number, meshId: string, meshType: string): void;

  // --- Tìm + active sub-device ---
  searchSubDevices(
    homeId: number,
    meshId: string,
    meshType: string,
    timeoutSec: number
  ): void; // -> onMeshDeviceFound
  activateSubDevice(
    homeId: number,
    meshId: string,
    meshType: string,
    mac: string,
    timeoutSec: number
  ): Promise<MeshSubDevice>;

  // --- Điều khiển DP qua mesh ---
  publishMeshDps(
    homeId: number,
    meshId: string,
    meshType: string,
    nodeId: string,
    pcc: string,
    dpsJson: string
  ): Promise<void>;
  multicastMeshDps(
    homeId: number,
    meshId: string,
    meshType: string,
    localId: string,
    pcc: string,
    dpsJson: string
  ): Promise<void>;

  // Event emitter plumbing (bắt buộc cho NativeEventEmitter)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaMesh');
