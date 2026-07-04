#import "TuyaTimer.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaTimer (iOS) — WIRED: getTimerList + removeTimer (ThingSmartTimer, key theo task/bizId/bizType).
// Verbatim: docs/research/tuya-home-sdk-device-control.md (ThingSmartTimer header).
// TODO: addTimer/updateTimer/updateTimerStatus — chữ ký đầy đủ (time/dps/status/isAppPush) + map inputJson cần verify.
// ThingSmartTimer KHÔNG có sharedInstance (đã verify header ThingSmartTimerKit) — alloc/init và giữ
// strong ref trong property để request async không bị dealloc/cancel giữa chừng.
//    removeTimerWithTask xoá theo task (KHÔNG theo timerIds — iOS không expose per-id verbatim).
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-device-control.md (timer).", what],
         nil);
}

static NSString *TuyaJsonStr(id obj) {
  if (![obj isKindOfClass:[NSDictionary class]]) return @"{}";
  if (![NSJSONSerialization isValidJSONObject:obj]) return @"{}";
  NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"{}";
}

@interface TuyaTimer ()
@property (nonatomic, strong) ThingSmartTimer *timer;
@end

@implementation TuyaTimer

RCT_EXPORT_MODULE()

- (ThingSmartTimer *)timer {
  if (!_timer) { _timer = [[ThingSmartTimer alloc] init]; }
  return _timer;
}

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
             reject:(RCTPromiseRejectBlock)reject {
  // timerIds bỏ qua trên iOS — removeTimerWithTask xoá toàn bộ timer của task/bizId/bizType.
  [self.timer removeTimerWithTask:taskName
                            bizId:bizId
                          bizType:(NSUInteger)bizType.integerValue
                          success:^{ resolve(nil); }
                          failure:^(NSError *e) { reject(@"remove_timer_error", e.localizedDescription, e); }];
}

- (void)getTimerList:(NSString *)taskName
               bizId:(NSString *)bizId
             bizType:(NSString *)bizType
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  [self.timer getTimerListWithTask:taskName
                             bizId:bizId
                           bizType:(NSUInteger)bizType.integerValue
                           success:^(NSArray<ThingTimerModel *> *list) {
    NSMutableArray *out = [NSMutableArray array];
    for (ThingTimerModel *t in list) {
      [out addObject:@{
        @"timerId": t.timerId ?: @"",
        @"time": t.time ?: @"",
        @"loops": t.loops ?: @"",
        @"status": @(t.status),
        @"dpsJson": TuyaJsonStr(t.dps),
        @"aliasName": t.aliasName ?: @"",
      }];
    }
    resolve(out);
  } failure:^(NSError *e) { reject(@"timer_list_error", e.localizedDescription, e); }];
}

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

@end
