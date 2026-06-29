#import "TuyaDevice.h"

// TuyaDevice (iOS) — DP/listener methods TODO-reject (implement bằng ThingSmartDevice + delegate trên Xcode).
// Event onDeviceStatus phát qua TuyaEventEmitter: [self emit:@"onDeviceStatus" body:...] khi impl xong.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — implement bằng ThingSmartDevice trên Xcode.", what],
         nil);
}

@implementation TuyaDevice

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents { return @[@"onDeviceStatus"]; }

- (void)publishDps:(NSString *)devId
           dpsJson:(NSString *)dpsJson
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"publishDps", reject); }

- (void)getDps:(NSString *)devId
       resolve:(RCTPromiseResolveBlock)resolve
        reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getDps", reject); }

// Khi impl: set delegate device → [self emit:@"onDeviceStatus" body:@{@"devId":..., @"dpsJson":...}].
- (void)registerDeviceListener:(NSString *)devId {}
- (void)unregisterDeviceListener:(NSString *)devId {}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) — không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaDeviceSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaDevice"; }

@end
