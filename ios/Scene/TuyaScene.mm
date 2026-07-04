#import "TuyaScene.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaScene (iOS) — WIRED: getSceneList + execute/enable/disable/delete (ThingSmartSceneManager + ThingSmartScene).
// TODO: detail/save/modify + build* condition/action (factory models) + device/city lists — chưa verbatim đủ.
// Event onSceneChange: iOS không có MQTT listener rõ → no-op (refresh list ở JS). Verbatim: docs/research/tuya-home-sdk-smart-scenes.md.
// ⚠️ Verify: ThingSmartSceneModel property (ruleGenre/displayColor/coverIcon — chưa map).
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-smart-scenes.md.", what],
         nil);
}

// ThingSmartScene không có init theo sceneId (đã verify header ThingSmartSceneCoreKit) — chỉ nhận
// ThingSmartSceneModel, nên dựng model tối thiểu chỉ có sceneId. Call site phải giữ scene sống tới khi
// callback về (capture vào block) vì instance sở hữu request đang bay (SDK có cancelRequest).
static ThingSmartScene *TuyaSceneById(NSString *sceneId) {
  ThingSmartSceneModel *model = [[ThingSmartSceneModel alloc] init];
  model.sceneId = sceneId;
  return [ThingSmartScene sceneWithSceneModel:model];
}

@implementation TuyaScene

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents { return @[@"onSceneChange"]; }

// ---------- List / detail ----------
- (void)getSceneList:(double)homeId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartSceneManager sharedInstance] getSceneListWithHomeId:(long long)homeId
                                                          success:^(NSArray<ThingSmartSceneModel *> *list) {
    NSMutableArray *out = [NSMutableArray array];
    for (ThingSmartSceneModel *m in list) {
      // ⚠️ ruleGenre/displayColor/coverIcon chưa map (property cần verify); sceneId/name/enabled/matchType an toàn.
      [out addObject:@{
        @"sceneId": m.sceneId ?: @"",
        @"name": m.name ?: @"",
        @"ruleGenre": @0,
        @"enabled": @(m.enabled),
        @"matchType": @(m.matchType),
        @"displayColor": @"",
        @"coverIcon": @"",
      }];
    }
    resolve(out);
  } failure:^(NSError *e) { reject(@"scene_list_error", e.localizedDescription, e); }];
}

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
             reject:(RCTPromiseRejectBlock)reject {
  ThingSmartScene *scene = TuyaSceneById(sceneId);
  [scene deleteSceneWithHomeId:(long long)homeId
                       success:^(BOOL result) { (void)scene; resolve(nil); }
                       failure:^(NSError *e) { reject(@"delete_scene_error", e.localizedDescription, e); }];
}

// ---------- Execute / automation ----------
- (void)executeScene:(double)homeId
             sceneId:(NSString *)sceneId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  ThingSmartScene *scene = TuyaSceneById(sceneId);
  [scene executeSceneWithSuccess:^{ (void)scene; resolve(nil); }
                         failure:^(NSError *e) { reject(@"execute_scene_error", e.localizedDescription, e); }];
}

- (void)enableAutomation:(NSString *)sceneId
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  ThingSmartScene *scene = TuyaSceneById(sceneId);
  [scene enableSceneWithSuccess:^{ (void)scene; resolve(nil); }
                        failure:^(NSError *e) { reject(@"enable_scene_error", e.localizedDescription, e); }];
}

- (void)disableAutomation:(NSString *)sceneId
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  ThingSmartScene *scene = TuyaSceneById(sceneId);
  [scene disableSceneWithSuccess:^{ (void)scene; resolve(nil); }
                         failure:^(NSError *e) { reject(@"disable_scene_error", e.localizedDescription, e); }];
}

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

@end
