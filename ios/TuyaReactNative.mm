#import "TuyaReactNative.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// ⚠️ iOS: CHƯA build/verify (máy không có Xcode + ios_core_sdk.tar.gz).
// - `initSdk` đọc AppKey/AppSecret từ Info.plist (ThingSmartAppKey / ThingSmartAppSecret) →
//   [[ThingSmartSDK sharedInstance] startWithAppKey:secretKey:] (xem SETUP.md).
// - Các hàm còn lại để TODO-reject (giữ skeleton compile) — implement bằng Tuya iOS SDK
//   (ThingSmartUser / ThingSmartHomeManager / ThingSmartActivator / ThingSmartDevice) trên Xcode,
//   tham chiếu docs/research/tuya-m1-sdk-foundation.md.

static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — implement bằng Tuya iOS SDK trên Xcode.", what],
         nil);
}

@implementation TuyaReactNative

// ---------- Init ----------
- (void)initSdk:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  NSString *appKey = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ThingSmartAppKey"];
  NSString *appSecret = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ThingSmartAppSecret"];
  if (appKey.length == 0 || appSecret.length == 0) {
    reject(@"init_error", @"Thiếu ThingSmartAppKey/ThingSmartAppSecret trong Info.plist", nil);
    return;
  }
  [[ThingSmartSDK sharedInstance] startWithAppKey:appKey secretKey:appSecret];
  resolve(@YES);
}

- (void)getSdkVersion:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  resolve(@"thingsmart:ios");
}

- (void)destroySdk {
  // no-op (iOS SDK không cần onDestroy như Android)
}

// ---------- Auth ----------
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

// ---------- Home ----------
- (void)createHome:(NSString *)name
               lon:(double)lon
               lat:(double)lat
           geoName:(NSString *)geoName
             rooms:(NSArray *)rooms
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"createHome", reject); }

- (void)getHomeList:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getHomeList", reject); }

- (void)getHomeDetail:(double)homeId
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getHomeDetail", reject); }

// ---------- Pairing: Wi-Fi ----------
- (void)getPairingToken:(double)homeId
                resolve:(RCTPromiseResolveBlock)resolve
                 reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getPairingToken", reject); }

- (void)startWifiPairing:(NSString *)mode
                    ssid:(NSString *)ssid
                password:(NSString *)password
                   token:(NSString *)token
              timeoutSec:(double)timeoutSec
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startWifiPairing", reject); }

- (void)stopWifiPairing {}

// ---------- Pairing: BLE ----------
- (void)startBleScan:(double)timeoutSec {}
- (void)stopBleScan {}

- (void)startBlePairing:(double)homeId
                   uuid:(NSString *)uuid
              productId:(NSString *)productId
                address:(NSString *)address
             deviceType:(double)deviceType
             timeoutSec:(double)timeoutSec
                resolve:(RCTPromiseResolveBlock)resolve
                 reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startBlePairing", reject); }

// ---------- Device control ----------
- (void)publishDps:(NSString *)devId
           dpsJson:(NSString *)dpsJson
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"publishDps", reject); }

- (void)getDps:(NSString *)devId
       resolve:(RCTPromiseResolveBlock)resolve
        reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getDps", reject); }

- (void)registerDeviceListener:(NSString *)devId {}
- (void)unregisterDeviceListener:(NSString *)devId {}

// ---------- RN event emitter plumbing ----------
- (void)addListener:(NSString *)eventName {}
- (void)removeListeners:(double)count {}

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeTuyaReactNativeSpecJSI>(params);
}

+ (NSString *)moduleName
{
  return @"TuyaReactNative";
}

@end
