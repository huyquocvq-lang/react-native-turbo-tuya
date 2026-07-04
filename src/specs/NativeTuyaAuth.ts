import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaAuth — đăng ký/đăng nhập (email + third-party) + session + profile.
// Object type dùng trong Spec phải khai báo NGAY TẠI ĐÂY (codegen không follow import chéo file).
export type UserResult = {
  uid: string;
  email: string;
  nickName: string;
  sessionId: string;
  // Profile mở rộng (B3) — native điền nếu có, mặc định '' / 0.
  headPic: string;
  mobile: string;
  tempUnit: number; // 1 = Celsius, 2 = Fahrenheit
  timezoneId: string;
  countryCode: string; // iOS có trực tiếp; Android '' (không expose trên User bean)
  regionCode: string; // iOS có; Android '' (nằm trong User.domain)
};

export type LoginTerminal = {
  terminalId: string;
  platform: string;
  os: string;
  loginTime: number;
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

  // Auth: third-party. type: 'gg'=Google, 'ap'=Apple, 'fb'=Facebook.
  // Google BẮT BUỘC extraInfo='{"pubVersion":1}'; provider khác truyền '' nếu không có.
  thirdLogin(
    countryCode: string,
    token: string,
    type: string,
    extraInfo: string
  ): Promise<UserResult>;

  // Session
  isLoggedIn(): Promise<boolean>;
  /** REJECT mã 'no_user' nếu chưa đăng nhập (KHÔNG resolve null). */
  getCurrentUser(): Promise<UserResult>;
  /** Đồng bộ profile mới nhất từ server (updateUserInfo) rồi trả về; reject 'no_user' nếu chưa login. */
  syncUserInfo(): Promise<UserResult>;
  logout(): Promise<void>;
  /** Huỷ tài khoản (có 7 ngày hoàn tác); sau đó state về Login. */
  cancelAccount(): Promise<void>;

  // Profile
  updateNickname(nickName: string): Promise<void>;
  updateTempUnit(unit: number): Promise<void>; // 1=°C, 2=°F
  updateTimeZone(timezoneId: string): Promise<void>;
  updateAvatarByUrl(imageUrl: string): Promise<void>;

  // Login identity: email/phone bind or change via OTP.
  sendBindEmailCode(countryCode: string, email: string): Promise<void>;
  sendBindPhoneCode(countryCode: string, phone: string): Promise<void>;
  bindEmail(countryCode: string, email: string, code: string, sessionId: string): Promise<void>;
  bindMobile(countryCode: string, phone: string, code: string): Promise<void>;
  changeUserName(countryCode: string, code: string, sessionId: string, userName: string): Promise<void>;

  // Reset password qua OTP (không có changePassword khi đang login).
  resetEmailPassword(
    countryCode: string,
    email: string,
    code: string,
    newPassword: string
  ): Promise<void>;
  resetPhonePassword(
    countryCode: string,
    phone: string,
    code: string,
    newPassword: string
  ): Promise<void>;

  // Third-party bind/unbind (CẦN verify chữ ký native — xem note user-account).
  bindThirdParty(provider: string, token: string, extraInfo: string): Promise<void>;
  unbindThirdParty(provider: string): Promise<void>;
  getLinkedThirdParties(): Promise<string[]>;

  // Đa thiết bị (iOS verbatim; Android cần verify).
  getLoginTerminals(): Promise<LoginTerminal[]>;
  terminateSession(terminalId: string, logoutCode: string): Promise<void>;

  // Event emitter plumbing (cho onSessionExpired). Bắt buộc cho NativeEventEmitter.
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaAuth');
