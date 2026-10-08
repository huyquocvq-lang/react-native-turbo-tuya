#import "TuyaAuth.h"
#import "TuyaReject.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaAuth (iOS) - profile/session/reset/cancel/multi-device + email send-code/login/register theo selector
// (docs/research/tuya-home-sdk-user-account.md). thirdLogin ĐÃ wire (loginByAuth2WithType:, 2026-07-02,
// docs/research/tuya-ios-third-party-login.md). loginWithEmailCode + updateAvatarByUrl đã wire (verify header
// ThingSmartUser.h - ThingSmartBaseKit 5.8.12). bind/unbind/getLinked third-party: SDK iOS KHÔNG có API → stub.
// ⚠️ loginByEmail/registerByEmail là selector chuẩn Tuya (KHÔNG có verbatim trong note) - verify khi build;
//    sendVerifyCode dùng ThingSuccessBlock (signature void/id verify trên header).

// Reject mang mã lỗi Tuya THẬT: NSError.code + localizedDescription (giống TuyaPairing) - không gom về literal.
static void TuyaRejectNSError(RCTPromiseRejectBlock reject,
                              NSError *error,
                              NSString *fallbackCode,
                              NSString *fallbackMessage) {
  if (error) {
    TuyaRejectWithDomain(reject, [@(error.code) stringValue], error.localizedDescription, @"sdk");
  } else {
    TuyaRejectWithDomain(reject, fallbackCode, fallbackMessage, @"sdk");
  }
}

// API không tồn tại trong SDK iOS đang dùng → giữ mã 'ios_todo' (README) nhưng message nói rõ lý do.
static void TuyaUnsupported(NSString *what, NSString *why, RCTPromiseRejectBlock reject) {
  TuyaRejectWithDomain(reject, @"ios_todo",
                       [NSString stringWithFormat:@"%@ is not available on iOS: %@", what, why], @"sdk");
}

static NSString *const kNoThirdPartyApi =
    @"the Tuya iOS SDK in use (ThingSmartHomeKit 7.5.0.4 / ThingSmartBaseKit 5.8.12) has no API to bind, unbind "
    @"or list third-party accounts on a logged-in user (ThingSmartUser only offers loginByAuth2WithType:)";

static NSDictionary *TuyaUserMap(ThingSmartUser *u) {
  return @{
    @"uid": u.uid ?: @"",
    @"email": u.email ?: @"",
    @"nickName": u.nickname ?: @"",
    @"sessionId": u.sid ?: @"",
    @"headPic": u.headIconUrl ?: @"",
    @"mobile": u.phoneNumber ?: @"",
    @"tempUnit": @(u.tempUnit),
    @"timezoneId": u.timezoneId ?: @"",
    @"countryCode": u.countryCode ?: @"",
    @"regionCode": u.regionCode ?: @"",
  };
}

@implementation TuyaAuth

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents { return @[@"onSessionExpired"]; }

- (instancetype)init {
  if (self = [super init]) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onSessionInvalid)
                                                 name:ThingSmartUserNotificationUserSessionInvalid
                                               object:nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onSessionInvalid {
  // ⚠️ SDK < v5.1 có thể bắn nhiều lần - cân nhắc debounce ở JS.
  [self emit:@"onSessionExpired" body:@{ @"reason": @"session_invalid" }];
}

// ---------- Auth: email (luồng login iOS làm sau) ----------
- (void)sendVerifyCode:(NSString *)email
           countryCode:(NSString *)countryCode
                  type:(double)type
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  // type: 1 register, 2 login, 3 reset, 8 unregister.
  [[ThingSmartUser sharedInstance] sendVerifyCodeWithUserName:email
                                                       region:nil
                                                  countryCode:countryCode
                                                         type:(NSInteger)type
                                                      success:^{ resolve(nil); }
                                                      failure:^(NSError *e) { reject(@"send_code_error", e.localizedDescription, e); }];
}

- (void)registerWithEmail:(NSString *)countryCode
                    email:(NSString *)email
                 password:(NSString *)password
                     code:(NSString *)code
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] registerByEmail:countryCode
                                             email:email
                                          password:password
                                              code:code
                                           success:^{ resolve(TuyaUserMap([ThingSmartUser sharedInstance])); }
                                           failure:^(NSError *e) { reject(@"register_error", e.localizedDescription, e); }];
}

- (void)loginWithEmail:(NSString *)countryCode
                 email:(NSString *)email
              password:(NSString *)password
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] loginByEmail:countryCode
                                          email:email
                                       password:password
                                        success:^{ resolve(TuyaUserMap([ThingSmartUser sharedInstance])); }
                                        failure:^(NSError *e) { reject(@"login_error", e.localizedDescription, e); }];
}

- (void)loginWithEmailCode:(NSString *)countryCode
                     email:(NSString *)email
                      code:(NSString *)code
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject {
  // Code lấy từ sendVerifyCode(type 2). Selector verify trên header: loginWithEmail:countryCode:code:success:failure:.
  [[ThingSmartUser sharedInstance] loginWithEmail:email
                                      countryCode:countryCode
                                             code:code
                                          success:^{ resolve(TuyaUserMap([ThingSmartUser sharedInstance])); }
                                          failure:^(NSError *e) {
    TuyaRejectNSError(reject, e, @"login_error", @"Email verification-code login failed.");
  }];
}

- (void)thirdLogin:(NSString *)countryCode
             token:(NSString *)token
              type:(NSString *)type
         extraInfo:(NSString *)extraInfo
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject {
  // iOS dùng loginByAuth2WithType: (KHÁC Android `thirdLogin`). type: @"gg" Google (idToken),
  // @"ap" Apple (identityToken), @"fb" Facebook. extraInfo iOS là NSDictionary → parse JSON string
  // từ JS: Google {"pubVersion":1}; Apple {userIdentifier,email,nickname,snsNickname}.
  // Nguồn: docs/research/tuya-ios-third-party-login.md.
  // ⚠️ Verify khi build: chữ ký `loginByAuth2WithType:...` + kiểu accessToken trong ThingSmartUser.h.
  NSDictionary *extra = nil;
  if (extraInfo.length > 0) {
    NSData *data = [extraInfo dataUsingEncoding:NSUTF8StringEncoding];
    id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([parsed isKindOfClass:[NSDictionary class]]) extra = parsed;
  }
  [[ThingSmartUser sharedInstance] loginByAuth2WithType:type
                                            countryCode:countryCode
                                            accessToken:token
                                              extraInfo:extra
                                                success:^{ resolve(TuyaUserMap([ThingSmartUser sharedInstance])); }
                                                failure:^(NSError *e) { reject(@"third_login_error", e.localizedDescription, e); }];
}

// ---------- Session ----------
- (void)isLoggedIn:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { resolve(@([ThingSmartUser sharedInstance].isLogin)); }

- (void)getCurrentUser:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  ThingSmartUser *u = [ThingSmartUser sharedInstance];
  if (!u.isLogin) { reject(@"no_user", @"Chưa đăng nhập", nil); return; }
  resolve(TuyaUserMap(u));
}

- (void)syncUserInfo:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  // iOS: properties tự đồng bộ khi truy vấn; không có updateUserInfo riêng như Android → đọc cache hiện tại.
  ThingSmartUser *u = [ThingSmartUser sharedInstance];
  if (!u.isLogin) { reject(@"no_user", @"Chưa đăng nhập", nil); return; }
  resolve(TuyaUserMap(u));
}

- (void)logout:(RCTPromiseResolveBlock)resolve
        reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] loginOut:^{ resolve(nil); }
                                    failure:^(NSError *e) { reject(@"logout_error", e.localizedDescription, e); }];
}

- (void)cancelAccount:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] cancelAccount:^{ resolve(nil); }
                                         failure:^(NSError *e) { reject(@"cancel_account_error", e.localizedDescription, e); }];
}

// ---------- Profile ----------
- (void)updateNickname:(NSString *)nickName
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] updateNickname:nickName
                                          success:^{ resolve(nil); }
                                          failure:^(NSError *e) { reject(@"update_nickname_error", e.localizedDescription, e); }];
}

- (void)updateTempUnit:(double)unit
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] updateTempUnitWithTempUnit:(NSInteger)unit
                                                      success:^{ resolve(nil); }
                                                      failure:^(NSError *e) { reject(@"temp_unit_error", e.localizedDescription, e); }];
}

- (void)updateTimeZone:(NSString *)timezoneId
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] updateTimeZoneWithTimeZoneId:timezoneId
                                                        success:^{ resolve(nil); }
                                                        failure:^(NSError *e) { reject(@"timezone_error", e.localizedDescription, e); }];
}

- (void)updateAvatarByUrl:(NSString *)imageUrl
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  // SDK nhận thẳng URL → không cần tải ảnh về native. API bị Tuya đánh dấu deprecated ("maintain user avatar
  // by yourself"): server có thể trả USER_AVATAR_UPLOAD_REJECT_FOR_CUSTOMIZE → reject nguyên mã/lời SDK.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [[ThingSmartUser sharedInstance] updateAvatarWithImageUrl:imageUrl
                                                    success:^{ resolve(nil); }
                                                    failure:^(NSError *e) {
    TuyaRejectNSError(reject, e, @"update_avatar_error", @"Avatar update failed.");
  }];
#pragma clang diagnostic pop
}

// ---------- Login identity: bind/change email or phone via OTP ----------
- (void)sendBindEmailCode:(NSString *)countryCode
                    email:(NSString *)email
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] sendVerifyCodeWithUserName:email
                                                       region:nil
                                                  countryCode:countryCode
                                                         type:2
                                                      success:^{ resolve(nil); }
                                                      failure:^(NSError *e) { reject(@"send_bind_email_code_error", e.localizedDescription, e); }];
}

- (void)sendBindPhoneCode:(NSString *)countryCode
                    phone:(NSString *)phone
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] sendVerifyCodeWithUserName:phone
                                                       region:nil
                                                  countryCode:countryCode
                                                         type:2
                                                      success:^{ resolve(nil); }
                                                      failure:^(NSError *e) { reject(@"send_bind_phone_code_error", e.localizedDescription, e); }];
}

- (void)bindEmail:(NSString *)countryCode
            email:(NSString *)email
             code:(NSString *)code
        sessionId:(NSString *)sessionId
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] bindEmail:email
                             withCountryCode:countryCode
                                        code:code
                                         sId:sessionId
                                     success:^{ resolve(nil); }
                                     failure:^(NSError *e) { reject(@"bind_email_error", e.localizedDescription, e); }];
}

- (void)bindMobile:(NSString *)countryCode
             phone:(NSString *)phone
              code:(NSString *)code
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject {
  // iOS docs expose `changBindAccount` for the bound email/phone account. No separate bindMobile
  // selector is documented in the local SDK note, so phone binding/change uses this account path.
  [[ThingSmartUser sharedInstance] changBindAccount:phone
                                       countryCode:countryCode
                                              code:code
                                           success:^{ resolve(nil); }
                                           failure:^(NSError *e) { reject(@"bind_mobile_error", e.localizedDescription, e); }];
}

- (void)changeUserName:(NSString *)countryCode
                  code:(NSString *)code
             sessionId:(NSString *)sessionId
              userName:(NSString *)userName
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] changBindAccount:userName
                                       countryCode:countryCode
                                              code:code
                                           success:^{ resolve(nil); }
                                           failure:^(NSError *e) { reject(@"change_username_error", e.localizedDescription, e); }];
}

// ---------- Reset password (OTP) ----------
- (void)resetEmailPassword:(NSString *)countryCode
                     email:(NSString *)email
                      code:(NSString *)code
               newPassword:(NSString *)newPassword
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] resetPasswordByEmail:countryCode
                                                  email:email
                                            newPassword:newPassword
                                                   code:code
                                                success:^{ resolve(nil); }
                                                failure:^(NSError *e) { reject(@"reset_email_pw_error", e.localizedDescription, e); }];
}

- (void)resetPhonePassword:(NSString *)countryCode
                     phone:(NSString *)phone
                      code:(NSString *)code
               newPassword:(NSString *)newPassword
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] resetPasswordByPhone:countryCode
                                            phoneNumber:phone
                                            newPassword:newPassword
                                                   code:code
                                                success:^{ resolve(nil); }
                                                failure:^(NSError *e) { reject(@"reset_phone_pw_error", e.localizedDescription, e); }];
}

// ---------- Third-party bind/unbind/list ----------
// Đã soát toàn bộ header Thing* trong Pods + binary ThingSmartBaseKit: không có selector bind/unbind/list và
// không có API name thing.m.user.third.bind (Android 7.5.6 có IThingUser.bindThirdPlatform; unbind/list thì
// cả 2 nền tảng đều không có).
- (void)bindThirdParty:(NSString *)provider
                 token:(NSString *)token
             extraInfo:(NSString *)extraInfo
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaUnsupported(@"bindThirdParty", kNoThirdPartyApi, reject); }

- (void)unbindThirdParty:(NSString *)provider
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaUnsupported(@"unbindThirdParty", kNoThirdPartyApi, reject); }

- (void)getLinkedThirdParties:(RCTPromiseResolveBlock)resolve
                       reject:(RCTPromiseRejectBlock)reject {
  TuyaUnsupported(@"getLinkedThirdParties", kNoThirdPartyApi, reject);
}

// ---------- Multi-device login ----------
- (void)getLoginTerminals:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] getLoginTerminalListWithSuccess:^(NSArray<ThingSmartLoginTerminalModel *> *list) {
    NSMutableArray *out = [NSMutableArray array];
    for (ThingSmartLoginTerminalModel *t in list) {
      [out addObject:@{
        @"terminalId": t.terminalId ?: @"",
        @"platform": t.platform ?: @"",
        @"os": t.os ?: @"",
        @"loginTime": @(t.loginTime),
      }];
    }
    resolve(out);
  } failure:^(NSError *e) { reject(@"login_terminals_error", e.localizedDescription, e); }];
}

- (void)terminateSession:(NSString *)terminalId
              logoutCode:(NSString *)logoutCode
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartUser sharedInstance] terminateSessionOnDevice:terminalId
                                                 logoutCode:logoutCode
                                                    success:^(BOOL r) { resolve(nil); }
                                                    failure:^(NSError *e) { reject(@"terminate_session_error", e.localizedDescription, e); }];
}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) - không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaAuthSpecJSI>(params);
}

@end
