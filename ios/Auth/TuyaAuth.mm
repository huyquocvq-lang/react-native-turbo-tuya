#import "TuyaAuth.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaAuth (iOS) — chỉ isLoggedIn đã wire; còn lại TODO-reject (implement bằng ThingSmartUser
// trên Xcode, selector đúng đã ghi trong docs/audit + research note). Skeleton compile được.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — implement bằng ThingSmartUser trên Xcode.", what],
         nil);
}

@implementation TuyaAuth

RCT_EXPORT_MODULE()

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

- (void)isLoggedIn:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { resolve(@([ThingSmartUser sharedInstance].isLogin)); }

- (void)getCurrentUser:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getCurrentUser", reject); }

- (void)logout:(RCTPromiseResolveBlock)resolve
        reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"logout", reject); }

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaAuthSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaAuth"; }

@end
