#import "TuyaTimer.h"

// TuyaTimer (iOS) — TODO-reject. Wire bằng ThingSmartTimer (addTimerWithTask:loops:bizId:bizType:time:dps:status:
// isAppPush:aliasName:.../getTimerListWithTask:bizId:bizType:/updateTimerStatusWithTask:.../removeTimerWithTask:...)
// trên Xcode — selector verbatim ở docs/research/tuya-home-sdk-device-control.md. Android wired.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-device-control.md (timer).", what],
         nil);
}

@implementation TuyaTimer

RCT_EXPORT_MODULE()

- (void)addTimer:(NSString *)inputJson
         resolve:(RCTPromiseResolveBlock)resolve
          reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"addTimer", reject); }

- (void)updateTimer:(NSString *)timerId
         inputJson:(NSString *)inputJson
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"updateTimer", reject); }

- (void)removeTimer:(NSString *)taskName
              bizId:(NSString *)bizId
            bizType:(NSString *)bizType
           timerIds:(NSArray *)timerIds
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"removeTimer", reject); }

- (void)getTimerList:(NSString *)taskName
               bizId:(NSString *)bizId
             bizType:(NSString *)bizType
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getTimerList", reject); }

- (void)updateTimerStatus:(NSString *)taskName
                    bizId:(NSString *)bizId
                  bizType:(NSString *)bizType
                 timerIds:(NSArray *)timerIds
                       op:(NSString *)op
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"updateTimerStatus", reject); }

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaTimerSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaTimer"; }

@end
