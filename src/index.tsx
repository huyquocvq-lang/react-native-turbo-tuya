import { NativeEventEmitter } from 'react-native';
import TuyaCore from './specs/NativeTuyaCore';
import TuyaAuth from './specs/NativeTuyaAuth';
import TuyaHome from './specs/NativeTuyaHome';
import TuyaPairing from './specs/NativeTuyaPairing';
import TuyaDevice from './specs/NativeTuyaDevice';
import TuyaOta from './specs/NativeTuyaOta';
import TuyaScene from './specs/NativeTuyaScene';
import TuyaTimer from './specs/NativeTuyaTimer';
import TuyaMessage from './specs/NativeTuyaMessage';
import TuyaMember from './specs/NativeTuyaMember';
import TuyaMatter from './specs/NativeTuyaMatter';
import TuyaMesh from './specs/NativeTuyaMesh';

// --- Re-export type kết quả (khai báo inline trong từng spec do ràng buộc codegen) ---
export type { UserResult, LoginTerminal } from './specs/NativeTuyaAuth';
export type { HomeResult, HomeDeviceItem, WeatherSketch } from './specs/NativeTuyaHome';
export type { DeviceResult } from './specs/NativeTuyaPairing';
export type { DeviceSnapshot } from './specs/NativeTuyaDevice';
export type { UpgradeInfo } from './specs/NativeTuyaOta';
export type {
  SceneSummary,
  SceneDetail,
  SaveSceneResult,
  SceneDeviceItem,
  SceneCityItem,
} from './specs/NativeTuyaScene';
export type { TimerItem } from './specs/NativeTuyaTimer';
export type {
  TuyaMessageItem,
  TuyaMessagePage,
  TuyaMessageHasNew,
  TuyaDndPeriod,
} from './specs/NativeTuyaMessage';
export type { Member, InvitationResult } from './specs/NativeTuyaMember';
export type {
  MatterSetupPayload,
  MatterConnectResult,
  MatterPairedDevice,
} from './specs/NativeTuyaMatter';
export type { MeshInfo, MeshSubDevice } from './specs/NativeTuyaMesh';

// --- Sub-module theo tính năng (truy cập trực tiếp nếu muốn) ---
export {
  TuyaCore,
  TuyaAuth,
  TuyaHome,
  TuyaPairing,
  TuyaDevice,
  TuyaOta,
  TuyaScene,
  TuyaTimer,
  TuyaMessage,
  TuyaMember,
  TuyaMatter,
  TuyaMesh,
};

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

export type SessionExpiredEvent = { reason?: string };

export type OtaProgressEvent = { devId: string; type: number; progress: number };
export type OtaStatusEvent = { devId: string; type: number; status: number };
export type OtaSuccessEvent = { devId: string; type: number };
export type OtaFailureEvent = { devId: string; type?: number; code: string; message?: string };

export type SceneChangeEvent = {
  type: string; // 'add' | 'update' | 'delete' | 'enable' | 'disable'
  sceneId: string;
};

export type HomeChangeEvent = {
  // type: 'homeAdded' | 'homeInvite' | 'homeRemoved' | 'homeInfoChanged' | 'sharedDeviceList'
  //     | 'sharedGroupList' | 'serverConnected' | 'deviceAdded' | 'deviceRemoved'
  //     | 'groupAdded' | 'groupRemoved' | 'meshAdded'
  type: string;
  homeId?: number;
  homeName?: string;
  devId?: string;
  groupId?: number;
  meshId?: string;
  devIds?: string[];
};

export type MatterDeviceFoundEvent = { dataJson?: string };
export type MatterAttestationEvent = { code?: number };
export type MatterErrorEvent = { code: string; message?: string };

export type MeshDeviceFoundEvent = { dataJson?: string };
export type MeshDpUpdateEvent = {
  nodeId: string;
  dpsJson?: string;
  isFromLocal?: boolean;
};
export type MeshStatusChangedEvent = {
  onlineJson?: string;
  offlineJson?: string;
  gwId?: string;
};

export type Subscription = { remove(): void };

/**
 * Facade phẳng gộp 9 TurboModule — giữ tương thích `Tuya.<method>()`.
 * Mỗi tính năng là 1 native module riêng (Core/Auth/Home/Pairing/Device/Ota/Scene/Timer/Message);
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
  syncUserInfo: TuyaAuth.syncUserInfo,
  logout: TuyaAuth.logout,
  cancelAccount: TuyaAuth.cancelAccount,
  updateNickname: TuyaAuth.updateNickname,
  updateTempUnit: TuyaAuth.updateTempUnit,
  updateTimeZone: TuyaAuth.updateTimeZone,
  updateAvatarByUrl: TuyaAuth.updateAvatarByUrl,
  sendBindEmailCode: TuyaAuth.sendBindEmailCode,
  sendBindPhoneCode: TuyaAuth.sendBindPhoneCode,
  bindEmail: TuyaAuth.bindEmail,
  bindMobile: TuyaAuth.bindMobile,
  changeUserName: TuyaAuth.changeUserName,
  resetEmailPassword: TuyaAuth.resetEmailPassword,
  resetPhonePassword: TuyaAuth.resetPhonePassword,
  bindThirdParty: TuyaAuth.bindThirdParty,
  unbindThirdParty: TuyaAuth.unbindThirdParty,
  getLinkedThirdParties: TuyaAuth.getLinkedThirdParties,
  getLoginTerminals: TuyaAuth.getLoginTerminals,
  terminateSession: TuyaAuth.terminateSession,
  // Home
  createHome: TuyaHome.createHome,
  getHomeList: TuyaHome.getHomeList,
  getHomeDetail: TuyaHome.getHomeDetail,
  getHomeDeviceList: TuyaHome.getHomeDeviceList,
  updateHome: TuyaHome.updateHome,
  dismissHome: TuyaHome.dismissHome,
  getHomeWeatherSketch: TuyaHome.getHomeWeatherSketch,
  getHomeWeatherDetail: TuyaHome.getHomeWeatherDetail,
  startHomeChangeListener: TuyaHome.startHomeChangeListener,
  stopHomeChangeListener: TuyaHome.stopHomeChangeListener,
  startHomeStatusListener: TuyaHome.startHomeStatusListener,
  stopHomeStatusListener: TuyaHome.stopHomeStatusListener,
  // Pairing
  getPairingToken: TuyaPairing.getPairingToken,
  startWifiPairing: TuyaPairing.startWifiPairing,
  startWifiPairingAuto: TuyaPairing.startWifiPairingAuto,
  stopWifiPairing: TuyaPairing.stopWifiPairing,
  startBleScan: TuyaPairing.startBleScan,
  stopBleScan: TuyaPairing.stopBleScan,
  startBlePairing: TuyaPairing.startBlePairing,
  startBleWifiPairing: TuyaPairing.startBleWifiPairing,
  stopBleWifiPairing: TuyaPairing.stopBleWifiPairing,
  startSubDevicePairing: TuyaPairing.startSubDevicePairing,
  stopSubDevicePairing: TuyaPairing.stopSubDevicePairing,
  startGatewayPairing: TuyaPairing.startGatewayPairing,
  startQrPairing: TuyaPairing.startQrPairing,
  startWiredPairing: TuyaPairing.startWiredPairing,
  destroyActivator: TuyaPairing.destroyActivator,
  // Device
  publishDps: TuyaDevice.publishDps,
  getDps: TuyaDevice.getDps,
  registerDeviceListener: TuyaDevice.registerDeviceListener,
  unregisterDeviceListener: TuyaDevice.unregisterDeviceListener,
  renameDevice: TuyaDevice.renameDevice,
  removeDevice: TuyaDevice.removeDevice,
  resetFactory: TuyaDevice.resetFactory,
  getWifiSignal: TuyaDevice.getWifiSignal,
  queryDp: TuyaDevice.queryDp,
  getDeviceSnapshot: TuyaDevice.getDeviceSnapshot,
  isDeviceOnline: TuyaDevice.isDeviceOnline,
  isCloudConnected: TuyaDevice.isCloudConnected,
  publishDpsWithMode: TuyaDevice.publishDpsWithMode,
  publishDpsWithChannels: TuyaDevice.publishDpsWithChannels,
  publishDpsAwaitAck: TuyaDevice.publishDpsAwaitAck,
  sendCacheDps: TuyaDevice.sendCacheDps,
  bleConnect: TuyaDevice.bleConnect,
  bleDisconnect: TuyaDevice.bleDisconnect,
  isBleLocalOnline: TuyaDevice.isBleLocalOnline,
  // Ota
  checkFirmwareUpgrade: TuyaOta.checkFirmwareUpgrade,
  startFirmwareUpgrade: TuyaOta.startFirmwareUpgrade,
  cancelFirmwareUpgrade: TuyaOta.cancelFirmwareUpgrade,
  confirmWarningUpgrade: TuyaOta.confirmWarningUpgrade,
  getAutoUpgradeSwitch: TuyaOta.getAutoUpgradeSwitch,
  setAutoUpgradeSwitch: TuyaOta.setAutoUpgradeSwitch,
  // Scene
  getSceneList: TuyaScene.getSceneList,
  getSceneDetail: TuyaScene.getSceneDetail,
  saveScene: TuyaScene.saveScene,
  modifyScene: TuyaScene.modifyScene,
  deleteScene: TuyaScene.deleteScene,
  executeScene: TuyaScene.executeScene,
  enableAutomation: TuyaScene.enableAutomation,
  disableAutomation: TuyaScene.disableAutomation,
  enableAutomationWithTime: TuyaScene.enableAutomationWithTime,
  buildDeviceCondition: TuyaScene.buildDeviceCondition,
  buildWeatherCondition: TuyaScene.buildWeatherCondition,
  buildTimerCondition: TuyaScene.buildTimerCondition,
  buildGeofenceCondition: TuyaScene.buildGeofenceCondition,
  buildDeviceAction: TuyaScene.buildDeviceAction,
  buildDelayAction: TuyaScene.buildDelayAction,
  buildTriggerSceneAction: TuyaScene.buildTriggerSceneAction,
  buildAutomationToggleAction: TuyaScene.buildAutomationToggleAction,
  buildNotificationAction: TuyaScene.buildNotificationAction,
  getConditionDeviceList: TuyaScene.getConditionDeviceList,
  getActionDeviceList: TuyaScene.getActionDeviceList,
  getCityListByCountryCode: TuyaScene.getCityListByCountryCode,
  getCityByLocation: TuyaScene.getCityByLocation,
  registerSceneChangeListener: TuyaScene.registerSceneChangeListener,
  unregisterSceneChangeListener: TuyaScene.unregisterSceneChangeListener,
  // Timer
  addTimer: TuyaTimer.addTimer,
  updateTimer: TuyaTimer.updateTimer,
  removeTimer: TuyaTimer.removeTimer,
  getTimerList: TuyaTimer.getTimerList,
  updateTimerStatus: TuyaTimer.updateTimerStatus,
  // Message (push + message-center + DND)
  registerDevice: TuyaMessage.registerDevice,
  unregisterDevice: TuyaMessage.unregisterDevice,
  getMessageList: TuyaMessage.getMessageList,
  getMessageListByType: TuyaMessage.getMessageListByType,
  getMessageDetailList: TuyaMessage.getMessageDetailList,
  getMessageHasNew: TuyaMessage.getMessageHasNew,
  markMessagesRead: TuyaMessage.markMessagesRead,
  deleteMessages: TuyaMessage.deleteMessages,
  deleteMessagesByType: TuyaMessage.deleteMessagesByType,
  getPushStatus: TuyaMessage.getPushStatus,
  setPushStatus: TuyaMessage.setPushStatus,
  getPushStatusByType: TuyaMessage.getPushStatusByType,
  setPushStatusByType: TuyaMessage.setPushStatusByType,
  getDndStatus: TuyaMessage.getDndStatus,
  setDndStatus: TuyaMessage.setDndStatus,
  getDndList: TuyaMessage.getDndList,
  getOnceDndList: TuyaMessage.getOnceDndList,
  addDnd: TuyaMessage.addDnd,
  addOnceDnd: TuyaMessage.addOnceDnd,
  modifyDnd: TuyaMessage.modifyDnd,
  removeDnd: TuyaMessage.removeDnd,
  // Member (P3)
  queryMembers: TuyaMember.queryMembers,
  addMember: TuyaMember.addMember,
  updateMember: TuyaMember.updateMember,
  removeMember: TuyaMember.removeMember,
  createInvitation: TuyaMember.createInvitation,
  getInvitationList: TuyaMember.getInvitationList,
  cancelInvitation: TuyaMember.cancelInvitation,
  updateInvitedMember: TuyaMember.updateInvitedMember,
  joinHomeByCode: TuyaMember.joinHomeByCode,
  processInvitation: TuyaMember.processInvitation,
  transferHomeOwner: TuyaMember.transferHomeOwner,
  // Matter (P3)
  parseMatterSetupCode: TuyaMatter.parseSetupCode,
  connectMatterDevice: TuyaMatter.connectDevice,
  commissionMatterDevice: TuyaMatter.commissionDevice,
  startMatterDiscovery: TuyaMatter.startDiscovery,
  stopMatterDiscovery: TuyaMatter.stopDiscovery,
  continueMatterCommissioning: TuyaMatter.continueCommissioning,
  cancelMatterActivator: TuyaMatter.cancelActivator,
  // Mesh (P3)
  createSigMesh: TuyaMesh.createSigMesh,
  createTuyaMesh: TuyaMesh.createTuyaMesh,
  getMeshList: TuyaMesh.getMeshList,
  startMeshClient: TuyaMesh.startMeshClient,
  stopMeshClient: TuyaMesh.stopMeshClient,
  searchMeshSubDevices: TuyaMesh.searchSubDevices,
  activateMeshSubDevice: TuyaMesh.activateSubDevice,
  publishMeshDps: TuyaMesh.publishMeshDps,
  multicastMeshDps: TuyaMesh.multicastMeshDps,
};

export default Tuya;

export const TuyaEvents = {
  DEVICE_STATUS: 'onDeviceStatus',
  PAIRING_PROGRESS: 'onPairingProgress',
  BLE_SCAN: 'onBleScan',
  SESSION_EXPIRED: 'onSessionExpired',
  OTA_PROGRESS: 'onOtaProgress',
  OTA_STATUS: 'onOtaStatusChanged',
  OTA_SUCCESS: 'onOtaSuccess',
  OTA_FAILURE: 'onOtaFailure',
  SCENE_CHANGE: 'onSceneChange',
  HOME_CHANGE: 'onHomeChange',
  MATTER_DEVICE_FOUND: 'onMatterDeviceFound',
  MATTER_ATTESTATION: 'onMatterAttestation',
  MATTER_ERROR: 'onMatterError',
  MESH_DEVICE_FOUND: 'onMeshDeviceFound',
  MESH_DP_UPDATE: 'onMeshDpUpdate',
  MESH_STATUS_CHANGED: 'onMeshStatusChanged',
} as const;

// Mỗi nhóm event đi qua module phát ra nó (đều implement addListener/removeListeners).
const deviceEmitter = new NativeEventEmitter(TuyaDevice as never);
const pairingEmitter = new NativeEventEmitter(TuyaPairing as never);
const authEmitter = new NativeEventEmitter(TuyaAuth as never);
const otaEmitter = new NativeEventEmitter(TuyaOta as never);
const sceneEmitter = new NativeEventEmitter(TuyaScene as never);
const homeEmitter = new NativeEventEmitter(TuyaHome as never);
const matterEmitter = new NativeEventEmitter(TuyaMatter as never);
const meshEmitter = new NativeEventEmitter(TuyaMesh as never);

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

export function onSessionExpired(
  listener: (event: SessionExpiredEvent) => void
): Subscription {
  return authEmitter.addListener(TuyaEvents.SESSION_EXPIRED, (event: Object) =>
    listener(event as unknown as SessionExpiredEvent)
  );
}

export function onOtaProgress(
  listener: (event: OtaProgressEvent) => void
): Subscription {
  return otaEmitter.addListener(TuyaEvents.OTA_PROGRESS, (event: Object) =>
    listener(event as unknown as OtaProgressEvent)
  );
}

export function onOtaStatusChanged(
  listener: (event: OtaStatusEvent) => void
): Subscription {
  return otaEmitter.addListener(TuyaEvents.OTA_STATUS, (event: Object) =>
    listener(event as unknown as OtaStatusEvent)
  );
}

export function onOtaSuccess(
  listener: (event: OtaSuccessEvent) => void
): Subscription {
  return otaEmitter.addListener(TuyaEvents.OTA_SUCCESS, (event: Object) =>
    listener(event as unknown as OtaSuccessEvent)
  );
}

export function onOtaFailure(
  listener: (event: OtaFailureEvent) => void
): Subscription {
  return otaEmitter.addListener(TuyaEvents.OTA_FAILURE, (event: Object) =>
    listener(event as unknown as OtaFailureEvent)
  );
}

export function onSceneChange(
  listener: (event: SceneChangeEvent) => void
): Subscription {
  return sceneEmitter.addListener(TuyaEvents.SCENE_CHANGE, (event: Object) =>
    listener(event as unknown as SceneChangeEvent)
  );
}

export function onHomeChange(
  listener: (event: HomeChangeEvent) => void
): Subscription {
  return homeEmitter.addListener(TuyaEvents.HOME_CHANGE, (event: Object) =>
    listener(event as unknown as HomeChangeEvent)
  );
}

export function onMatterDeviceFound(
  listener: (event: MatterDeviceFoundEvent) => void
): Subscription {
  return matterEmitter.addListener(TuyaEvents.MATTER_DEVICE_FOUND, (event: Object) =>
    listener(event as unknown as MatterDeviceFoundEvent)
  );
}

export function onMatterAttestation(
  listener: (event: MatterAttestationEvent) => void
): Subscription {
  return matterEmitter.addListener(TuyaEvents.MATTER_ATTESTATION, (event: Object) =>
    listener(event as unknown as MatterAttestationEvent)
  );
}

export function onMatterError(
  listener: (event: MatterErrorEvent) => void
): Subscription {
  return matterEmitter.addListener(TuyaEvents.MATTER_ERROR, (event: Object) =>
    listener(event as unknown as MatterErrorEvent)
  );
}

export function onMeshDeviceFound(
  listener: (event: MeshDeviceFoundEvent) => void
): Subscription {
  return meshEmitter.addListener(TuyaEvents.MESH_DEVICE_FOUND, (event: Object) =>
    listener(event as unknown as MeshDeviceFoundEvent)
  );
}

export function onMeshDpUpdate(
  listener: (event: MeshDpUpdateEvent) => void
): Subscription {
  return meshEmitter.addListener(TuyaEvents.MESH_DP_UPDATE, (event: Object) =>
    listener(event as unknown as MeshDpUpdateEvent)
  );
}

export function onMeshStatusChanged(
  listener: (event: MeshStatusChangedEvent) => void
): Subscription {
  return meshEmitter.addListener(TuyaEvents.MESH_STATUS_CHANGED, (event: Object) =>
    listener(event as unknown as MeshStatusChangedEvent)
  );
}
