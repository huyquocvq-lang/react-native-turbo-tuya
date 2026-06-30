#import "TuyaHome.h"

// TuyaHome (iOS) — TODO-reject (implement bằng ThingSmartHomeManager/ThingSmartHome trên Xcode).
// Weather: getHomeWeatherSketchWithSuccess:/getHomeWeatherDetailWithOption: (ThingSmartHome — tự dùng lat/lon).
// Listeners: ThingSmartHomeManagerDelegate (cấp manager) + ThingSmartHomeDelegate (cấp home) → [self emit:@"onHomeChange" ...].
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — implement bằng ThingSmartHomeManager trên Xcode.", what],
         nil);
}

@implementation TuyaHome

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents { return @[@"onHomeChange"]; }

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

- (void)updateHome:(double)homeId
              name:(NSString *)name
               lon:(double)lon
               lat:(double)lat
           geoName:(NSString *)geoName
             rooms:(NSArray *)rooms
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"updateHome", reject); }

- (void)dismissHome:(double)homeId
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"dismissHome", reject); }

// ---------- Weather ----------
- (void)getHomeWeatherSketch:(double)homeId
                         lon:(double)lon
                         lat:(double)lat
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getHomeWeatherSketch", reject); }

- (void)getHomeWeatherDetail:(double)homeId
                       limit:(double)limit
                    unitJson:(NSString *)unitJson
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getHomeWeatherDetail", reject); }

// ---------- Listeners (delegate → [self emit:@"onHomeChange" ...] khi impl) ----------
- (void)startHomeChangeListener:(RCTPromiseResolveBlock)resolve
                         reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startHomeChangeListener", reject); }

- (void)stopHomeChangeListener:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"stopHomeChangeListener", reject); }

- (void)startHomeStatusListener:(double)homeId
                        resolve:(RCTPromiseResolveBlock)resolve
                         reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startHomeStatusListener", reject); }

- (void)stopHomeStatusListener:(double)homeId
                       resolve:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"stopHomeStatusListener", reject); }

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) — không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaHomeSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaHome"; }

@end
