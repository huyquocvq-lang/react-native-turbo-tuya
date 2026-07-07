import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaScene - ngữ cảnh thông minh (tap-to-run + automation).
// Phát event: onSceneChange (realtime add/update/delete/enable/disable) → cần addListener/removeListeners.
// LƯU Ý codegen: KHÔNG union type (value luôn string - caller tự stringify); object type khai inline.
// condition/action truyền dưới dạng JSON string đã build (qua buildXxxCondition/buildXxxAction).
export type SceneSummary = {
  sceneId: string;
  name: string;
  ruleGenre: number; // 1 = tap-to-run, 2 = automation
  enabled: boolean; // chỉ ý nghĩa với automation
  matchType: number; // 1 = OR (any), 2 = AND (all)
  displayColor: string;
  coverIcon: string;
};

export type SceneDetail = {
  sceneId: string;
  name: string;
  ruleGenre: number;
  enabled: boolean;
  matchType: number;
  conditionsJson: string; // JSON array condition (raw từ SDK)
  actionsJson: string; // JSON array action (raw từ SDK)
  preConditionsJson: string;
};

// paramsJson (cho saveScene/modifyScene) = JSON object:
//   { name: string; ruleGenre: 1|2; matchType: 1|2; background: string;
//     conditionsJson: string ('[]' nếu tap-to-run); actionsJson: string (>=1); preConditionsJson: string }
// Dùng JSON string thay object param để gọn codegen 2 nền tảng.

export type SaveSceneResult = {
  sceneId: string;
  name: string;
  ruleGenre: number;
};

export type SceneDeviceItem = { devId: string; name: string };
export type SceneCityItem = { cityId: string; cityName: string };

export interface Spec extends TurboModule {
  // --- List / detail ---
  getSceneList(homeId: number): Promise<SceneSummary[]>;
  getSceneDetail(homeId: number, sceneId: string): Promise<SceneDetail>;

  // --- Create / modify / delete (paramsJson xem comment SaveSceneResult ở trên) ---
  saveScene(homeId: number, paramsJson: string): Promise<SaveSceneResult>;
  modifyScene(
    homeId: number,
    sceneId: string,
    paramsJson: string
  ): Promise<SaveSceneResult>;
  deleteScene(homeId: number, sceneId: string): Promise<boolean>;

  // --- Execute / automation control ---
  executeScene(homeId: number, sceneId: string): Promise<void>; // tap-to-run
  enableAutomation(sceneId: string): Promise<boolean>;
  disableAutomation(sceneId: string): Promise<boolean>;
  enableAutomationWithTime(sceneId: string, durationMs: number): Promise<boolean>; // Android-only

  // --- Builders (native build condition/action → trả JSON nạp vào saveScene) ---
  // op (toán tử): '==' | '<' | '>' | '<=' | '>=' (KHÔNG dùng tên 'operator' - keyword C++/ObjC++).
  // value luôn là string (số/enum/bool stringify).
  buildDeviceCondition(
    devId: string,
    dpId: string,
    op: string,
    value: string
  ): Promise<string>;
  buildWeatherCondition(
    cityId: string,
    cityName: string,
    weatherType: string,
    op: string,
    value: string
  ): Promise<string>;
  buildTimerCondition(
    timeZoneId: string,
    loops: string,
    time: string,
    date: string
  ): Promise<string>;
  buildGeofenceCondition(
    geoType: string, // 'reach' | 'exit'
    latitude: number,
    longitude: number,
    radius: number,
    title: string
  ): Promise<string>;
  buildDeviceAction(devId: string, dpId: string, value: string): Promise<string>;
  buildDelayAction(
    hours: number,
    minutes: number,
    seconds: number
  ): Promise<string>;
  buildTriggerSceneAction(
    sceneId: string,
    sceneName: string
  ): Promise<string>;
  buildAutomationToggleAction(
    sceneId: string,
    enable: boolean
  ): Promise<string>;
  buildNotificationAction(channel: string): Promise<string>; // 'message' | 'sms' | 'phone'

  // --- Helpers cho UI tạo scene ---
  getConditionDeviceList(homeId: number): Promise<SceneDeviceItem[]>;
  getActionDeviceList(homeId: number): Promise<SceneDeviceItem[]>;
  getCityListByCountryCode(countryCode: string): Promise<SceneCityItem[]>;
  getCityByLocation(
    latitude: number,
    longitude: number
  ): Promise<SceneCityItem>;

  // --- Realtime listener (Android MQTT; iOS refresh) → event onSceneChange ---
  registerSceneChangeListener(): void;
  unregisterSceneChangeListener(): void;

  // Event emitter plumbing (bắt buộc cho NativeEventEmitter)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaScene');
