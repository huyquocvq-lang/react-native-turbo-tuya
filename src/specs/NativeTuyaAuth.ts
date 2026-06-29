import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaAuth — đăng ký/đăng nhập (email + third-party) + session.
// Object type dùng trong Spec phải khai báo NGAY TẠI ĐÂY (codegen không follow import chéo file).
export type UserResult = {
  uid: string;
  email: string;
  nickName: string;
  sessionId: string;
};

export interface Spec extends TurboModule {
  // Auth: email — type: 1=register, 2=login, 3=reset password, 8=unregister
  sendVerifyCode(
    email: string,
    countryCode: string,
    type: number
  ): Promise<void>;
  registerWithEmail(
    countryCode: string,
    email: string,
    password: string,
    code: string
  ): Promise<UserResult>;
  loginWithEmail(
    countryCode: string,
    email: string,
    password: string
  ): Promise<UserResult>;
  loginWithEmailCode(
    countryCode: string,
    email: string,
    code: string
  ): Promise<UserResult>;

  // Auth: third-party (Google "gg" + idToken / Apple "ap")
  thirdLogin(
    countryCode: string,
    token: string,
    type: string,
    extraInfo: string
  ): Promise<UserResult>;

  // Session
  isLoggedIn(): Promise<boolean>;
  getCurrentUser(): Promise<UserResult>;
  logout(): Promise<void>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaAuth');
