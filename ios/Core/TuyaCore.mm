#import "TuyaCore.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>
#import <ThingSmartBusinessExtensionKit/ThingSmartBusinessExtensionKit.h>

// TuyaCore (iOS) — init/destroy SDK. AppKey/AppSecret đọc từ Info.plist
// (ThingSmartAppKey / ThingSmartAppSecret) → startWithAppKey:secretKey: (xem README.md).
@implementation TuyaCore

RCT_EXPORT_MODULE()

- (void)initSdk:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  NSString *appKey = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ThingSmartAppKey"];
  NSString *appSecret = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ThingSmartAppSecret"];
  if (appKey.length == 0 || appSecret.length == 0) {
    reject(@"init_error", @"Thiếu ThingSmartAppKey/ThingSmartAppSecret trong Info.plist", nil);
    return;
  }
  [[ThingSmartSDK sharedInstance] startWithAppKey:appKey secretKey:appSecret];
  // BusinessExtensionKit (token/pairing helpers) cần setupConfig khi là dependency.
  [ThingSmartBusinessExtensionConfig setupConfig];
  resolve(@YES);
}

- (void)getSdkVersion:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  // Tuya iOS không expose version API ổn định → trả version đã pin (pod ThingSmartHomeKit ~7.5).
  resolve(@"thingsmart:7.5.0");
}

- (void)destroySdk {
  // no-op (iOS SDK không cần onDestroy như Android)
}

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaCoreSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaCore"; }

@end
