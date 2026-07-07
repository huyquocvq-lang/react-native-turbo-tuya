import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaCore - khởi tạo SDK. Codegen chỉ parse file spec này.
// AppKey/AppSecret nạp native-only (Android: manifest meta-data; iOS: Info.plist) - KHÔNG truyền từ JS.
export interface Spec extends TurboModule {
  // Init (KHÔNG tham số data center; region đi theo DC của AppKey + countryCode lúc login)
  initSdk(): Promise<boolean>;
  getSdkVersion(): Promise<string>;
  destroySdk(): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaCore');
