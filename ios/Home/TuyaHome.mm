#import "TuyaHome.h"

// TuyaHome (iOS) — TODO-reject (implement bằng ThingSmartHomeManager/ThingSmartHome trên Xcode).
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — implement bằng ThingSmartHomeManager trên Xcode.", what],
         nil);
}

@implementation TuyaHome

RCT_EXPORT_MODULE()

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

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaHomeSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaHome"; }

@end
