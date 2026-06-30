#import "TuyaScene.h"

// TuyaScene (iOS) — SKELETON TODO-reject. Wire bằng ThingSmartSceneManager + ThingSmartScene +
// ThingSmartSceneConditionFactory/ActionFactory trên Xcode (selector verbatim ở docs/research/tuya-home-sdk-smart-scenes.md).
// Event onSceneChange phát qua TuyaEventEmitter khi wire (iOS không có MQTT listener rõ → refresh list).
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-smart-scenes.md.", what],
         nil);
}

@implementation TuyaScene

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents { return @[@"onSceneChange"]; }

// ---------- List / detail ----------
- (void)getSceneList:(double)homeId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getSceneList", reject); }

- (void)getSceneDetail:(double)homeId
               sceneId:(NSString *)sceneId
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getSceneDetail", reject); }

// ---------- Create / modify / delete ----------
- (void)saveScene:(double)homeId
       paramsJson:(NSString *)paramsJson
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"saveScene", reject); }

- (void)modifyScene:(double)homeId
            sceneId:(NSString *)sceneId
         paramsJson:(NSString *)paramsJson
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"modifyScene", reject); }

- (void)deleteScene:(double)homeId
            sceneId:(NSString *)sceneId
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"deleteScene", reject); }

// ---------- Execute / automation ----------
- (void)executeScene:(double)homeId
             sceneId:(NSString *)sceneId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"executeScene", reject); }

- (void)enableAutomation:(NSString *)sceneId
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"enableAutomation", reject); }

- (void)disableAutomation:(NSString *)sceneId
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"disableAutomation", reject); }

- (void)enableAutomationWithTime:(NSString *)sceneId
                       durationMs:(double)durationMs
                          resolve:(RCTPromiseResolveBlock)resolve
                           reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"enableAutomationWithTime", reject); }

// ---------- Builders ----------
- (void)buildDeviceCondition:(NSString *)devId
                        dpId:(NSString *)dpId
                          op:(NSString *)op
                       value:(NSString *)value
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"buildDeviceCondition", reject); }

- (void)buildWeatherCondition:(NSString *)cityId
                     cityName:(NSString *)cityName
                  weatherType:(NSString *)weatherType
                           op:(NSString *)op
                        value:(NSString *)value
                      resolve:(RCTPromiseResolveBlock)resolve
                       reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"buildWeatherCondition", reject); }

- (void)buildTimerCondition:(NSString *)timeZoneId
                      loops:(NSString *)loops
                       time:(NSString *)time
                       date:(NSString *)date
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"buildTimerCondition", reject); }

- (void)buildGeofenceCondition:(NSString *)geoType
                      latitude:(double)latitude
                     longitude:(double)longitude
                        radius:(double)radius
                         title:(NSString *)title
                       resolve:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"buildGeofenceCondition", reject); }

- (void)buildDeviceAction:(NSString *)devId
                     dpId:(NSString *)dpId
                    value:(NSString *)value
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"buildDeviceAction", reject); }

- (void)buildDelayAction:(double)hours
                 minutes:(double)minutes
                 seconds:(double)seconds
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"buildDelayAction", reject); }

- (void)buildTriggerSceneAction:(NSString *)sceneId
                      sceneName:(NSString *)sceneName
                        resolve:(RCTPromiseResolveBlock)resolve
                         reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"buildTriggerSceneAction", reject); }

- (void)buildAutomationToggleAction:(NSString *)sceneId
                             enable:(BOOL)enable
                            resolve:(RCTPromiseResolveBlock)resolve
                             reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"buildAutomationToggleAction", reject); }

- (void)buildNotificationAction:(NSString *)channel
                        resolve:(RCTPromiseResolveBlock)resolve
                         reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"buildNotificationAction", reject); }

// ---------- Helpers ----------
- (void)getConditionDeviceList:(double)homeId
                       resolve:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getConditionDeviceList", reject); }

- (void)getActionDeviceList:(double)homeId
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getActionDeviceList", reject); }

- (void)getCityListByCountryCode:(NSString *)countryCode
                         resolve:(RCTPromiseResolveBlock)resolve
                          reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getCityListByCountryCode", reject); }

- (void)getCityByLocation:(double)latitude
                longitude:(double)longitude
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getCityByLocation", reject); }

// ---------- Realtime listener ----------
- (void)registerSceneChangeListener {}
- (void)unregisterSceneChangeListener {}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter).

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaSceneSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaScene"; }

@end
