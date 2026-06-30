#import "TuyaAuth.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaAuth (iOS) — profile/session/reset/cancel/multi-device implement theo selector verbatim
// (docs/research/tuya-home-sdk-user-account.md). Email login/register/thirdLogin VẪN TODO-reject
// (luồng login iOS làm sau). bind/getLinked third-party chưa có selector verbatim → TODO.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-user-account.md.", what],
         nil);
}

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
  // ⚠️ SDK < v5.1 có thể bắn nhiều lần — cân nhắc debounce ở JS.
  [self emit:@"onSessionExpired" body:@{ @"reason": @"session_invalid" }];
}

// ---------- Auth: email (luồng login iOS làm sau) ----------
- (void)sendVerifyCode:(NSString *)email
           countryCode:(NSString *)countryCode
                  type:(double)type
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"sendVerifyCode", reject); }

- (void)registerWithEmail:(NSString *)countryCode
                    email:(NSString *)email
                 password:(NSString *)password
                     code:(NSString *)code
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"registerWithEmail", reject); }

- (void)loginWithEmail:(NSString *)countryCode
                 email:(NSString *)email
              password:(NSString *)password
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"loginWithEmail", reject); }

- (void)loginWithEmailCode:(NSString *)countryCode
                     email:(NSString *)email
                      code:(NSString *)code
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"loginWithEmailCode", reject); }

- (void)thirdLogin:(NSString *)countryCode
             token:(NSString *)token
              type:(NSString *)type
         extraInfo:(NSString *)extraInfo
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"thirdLogin", reject); }

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
  // updateAvatarWithImageUrl: DEPRECATED bởi Tuya — ưu tiên avatar preset. Để TODO.
  TuyaTODO(@"updateAvatarByUrl (deprecated)", reject);
}

// ---------- Reset password (OTP) ----------
- (void)resetEmailPassword:(NSString *)countryCode
                     email:(NSString *)email
                      code:(NSString *)code
               newPassword:(NSString *)newPassword
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject {
  // iOS reset email không cần countryCode.
  [[ThingSmartUser sharedInstance] resetPasswordByEmail:email
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

// ---------- Third-party bind (chưa có selector verbatim iOS — TODO) ----------
- (void)bindThirdParty:(NSString *)provider
                 token:(NSString *)token
             extraInfo:(NSString *)extraInfo
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"bindThirdParty", reject); }

- (void)unbindThirdParty:(NSString *)provider
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"unbindThirdParty", reject); }

- (void)getLinkedThirdParties:(RCTPromiseResolveBlock)resolve
                       reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getLinkedThirdParties", reject); }

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

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) — không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaAuthSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaAuth"; }

@end
