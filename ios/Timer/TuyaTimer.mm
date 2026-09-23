#import "TuyaTimer.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaTimer (iOS) - WIRED: addTimer + getTimerList + removeTimer (ThingSmartTimer, key theo task/bizId/bizType).
// Verbatim: docs/research/tuya-home-sdk-device-control.md (ThingSmartTimer header).
// TODO: updateTimer/updateTimerStatus - chữ ký đầy đủ + map inputJson cần verify.
// ThingSmartTimer KHÔNG có sharedInstance (đã verify header ThingSmartTimerKit) - alloc/init và giữ
// strong ref trong property để request async không bị dealloc/cancel giữa chừng.
//    removeTimerWithTask xoá theo task (KHÔNG theo timerIds - iOS không expose per-id verbatim).
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire - xem docs/research/tuya-home-sdk-device-control.md (timer).", what],
         nil);
}

static NSString *TuyaJsonStr(id obj) {
  if (![obj isKindOfClass:[NSDictionary class]]) return @"{}";
  if (![NSJSONSerialization isValidJSONObject:obj]) return @"{}";
  NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"{}";
}

static NSDictionary *TuyaJsonDict(id json) {
  if (![json isKindOfClass:[NSString class]]) return @{};
  NSData *d = [(NSString *)json dataUsingEncoding:NSUTF8StringEncoding];
  id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
  return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
}

static NSString *TuyaStr(id v, NSString *fallback) {
  return [v isKindOfClass:[NSString class]] ? (NSString *)v : fallback;
}

static BOOL TuyaBool(id v, BOOL fallback) {
  return [v isKindOfClass:[NSNumber class]] ? ((NSNumber *)v).boolValue : fallback;
}

// Hợp đồng JS dùng 'device' | 'group'; SDK nhận 0 = device, 1 = group.
static NSUInteger TuyaBizType(id bizType) {
  return [TuyaStr(bizType, @"device").lowercaseString isEqualToString:@"group"] ? 1 : 0;
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

// inputJson = { taskName, bizId, bizType, time 'HH:mm', loops (7 ký tự), dpsJson, status?, appPush?, aliasName? }.
// Thiếu field bắt buộc thì từ chối ngay: SDK chỉ trả -5 "param invalid" chung chung, khó lần ra thiếu cái gì.
- (void)addTimer:(NSString *)inputJson
         resolve:(RCTPromiseResolveBlock)resolve
          reject:(RCTPromiseRejectBlock)reject {
  NSDictionary *in = TuyaJsonDict(inputJson);
  NSString *task = TuyaStr(in[@"taskName"], @"");
  NSString *bizId = TuyaStr(in[@"bizId"], @"");
  NSString *time = TuyaStr(in[@"time"], @"");
  NSString *loops = TuyaStr(in[@"loops"], @"0000000");
  NSDictionary *dps = TuyaJsonDict(in[@"dpsJson"]);
  if (task.length == 0 || bizId.length == 0 || time.length == 0 || dps.count == 0) {
    reject(@"invalid_param", @"addTimer cần taskName, bizId, time và dpsJson khác rỗng", nil);
    return;
  }
  [self.timer addTimerWithTask:task
                         loops:loops
                         bizId:bizId
                       bizType:TuyaBizType(in[@"bizType"])
                          time:time
                           dps:dps
                        status:TuyaBool(in[@"status"], YES)
                     isAppPush:TuyaBool(in[@"appPush"], NO)
                     aliasName:TuyaStr(in[@"aliasName"], @"")
                       success:^{ resolve(nil); }
                       failure:^(NSError *e) { reject(@"add_timer_error", e.localizedDescription, e); }];
}

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
  // timerIds bỏ qua trên iOS - removeTimerWithTask xoá toàn bộ timer của task/bizId/bizType.
  [self.timer removeTimerWithTask:taskName
                            bizId:bizId
                          bizType:TuyaBizType(bizType)
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
                           bizType:TuyaBizType(bizType)
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
