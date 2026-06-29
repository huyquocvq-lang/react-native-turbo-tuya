import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaHome — quản lý home cơ bản (app dùng 1 nhà/user).
export type HomeResult = {
  homeId: number; // long → number (an toàn < 2^53)
  name: string;
  role: number; // 2=owner, 1=admin, 0=member, -1=custom, -999=invalid
  admin: boolean;
  lon: number;
  lat: number;
  geoName: string;
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
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaHome');
