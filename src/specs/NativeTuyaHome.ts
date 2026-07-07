import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaHome - quản lý home (app dùng 1 nhà/user) + weather + listeners.
// Phát event 'onHomeChange' (home add/remove/invite/info + device/group trong home) → addListener/removeListeners.
export type HomeResult = {
  homeId: number; // long → number (an toàn < 2^53)
  name: string;
  role: number; // 2=owner, 1=admin, 0=member, -1=custom, -999=invalid
  admin: boolean;
  lon: number;
  lat: number;
  geoName: string;
};

// 1 thiết bị thuộc home (map từ DeviceBean/ThingSmartDeviceModel) - đủ dùng cho màn device list.
export type HomeDeviceItem = {
  devId: string;
  name: string;
  productId: string;
  isOnline: boolean; // LAN hoặc cloud
  iconUrl: string;
};

export type WeatherSketch = {
  condition: string;
  temp: string;
  iconUrl: string;
  inIconUrl: string;
};

export interface Spec extends TurboModule {
  createHome(
    name: string,
    lon: number,
    lat: number,
    geoName: string,
    rooms: string[]
  ): Promise<HomeResult>;
  getHomeList(): Promise<HomeResult[]>;
  getHomeDetail(homeId: number): Promise<HomeResult>;
  // Danh sách thiết bị trong home (sau khi nạp home detail) → dùng cho màn device list.
  getHomeDeviceList(homeId: number): Promise<HomeDeviceItem[]>;
  // Cập nhật tên/vị trí/danh sách phòng của home.
  updateHome(
    homeId: number,
    name: string,
    lon: number,
    lat: number,
    geoName: string,
    rooms: string[]
  ): Promise<void>;
  // Giải tán/xoá toàn bộ home (chỉ owner).
  dismissHome(homeId: number): Promise<void>;

  // --- Weather (optional cho ice-bath) ---
  // iOS dùng homeId (ThingSmartHome tự lấy lat/lon); Android dùng lon/lat truyền vào.
  getHomeWeatherSketch(
    homeId: number,
    lon: number,
    lat: number
  ): Promise<WeatherSketch>;
  // limit = số ngày; unitJson = {"tempUnit","pressureUnit","windspeedUnit"}; trả JSON mảng theo ngày (DashBoardBean).
  getHomeWeatherDetail(
    homeId: number,
    limit: number,
    unitJson: string
  ): Promise<string>;

  // --- Listeners (phát event 'onHomeChange') ---
  // Cấp manager: home add/remove/invite/info-changed + shared device list.
  startHomeChangeListener(): Promise<void>;
  stopHomeChangeListener(): Promise<void>;
  // Cấp 1 home: device/group/mesh thêm-xoá trong home.
  startHomeStatusListener(homeId: number): Promise<void>;
  stopHomeStatusListener(homeId: number): Promise<void>;

  // Event emitter plumbing (bắt buộc cho NativeEventEmitter)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaHome');
