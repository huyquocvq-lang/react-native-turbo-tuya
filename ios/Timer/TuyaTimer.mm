#import "TuyaTimer.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaTimer (iOS) - WIRED ĐỦ: addTimer · updateTimer · getTimerList · removeTimer · updateTimerStatus.
// Chữ ký lấy VERBATIM từ header SDK thật: Pods/ThingSmartTimerKit/…/Headers/ThingSmartTimer.h (7.5.x).
// ThingSmartTimer KHÔNG có sharedInstance (đã verify header) - alloc/init và giữ strong ref trong property
// để request async không bị dealloc/cancel giữa chừng.
//
// Hợp đồng với JS (dùng chung với Android): thao tác theo TASK NAME; `timerIds` RỖNG = áp dụng cho CẢ TASK.
//   - removeTimer          → removeTimerWithTask (xoá cả task; iOS cũng có per-id nhưng JS chưa cần)
//   - updateTimerStatus    → timerIds rỗng: updateTimerTaskStatusWithTask ; có id: updateTimerStatusWithTimerIds
//   - `loops`: 7 ký tự, TRÁI→PHẢI = **Chủ Nhật → Thứ Bảy** (header nói rõ: "0100000 means every Monday").

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

// Hợp đồng JS dùng 'open' | 'close' | 'delete'; SDK nhận updateType - verbatim header:
// "`0`: disables the timer. `1`: enables the timer. `2`: deletes the timer."
// Mặc định về DELETE (giống Android `updateOp`) để op lạ không vô tình BẬT một lịch người dùng đã tắt.
static NSUInteger TuyaTimerUpdateType(NSString *op) {
  NSString *s = [TuyaStr(op, @"") lowercaseString];
  if ([s isEqualToString:@"open"]) return 1;
  if ([s isEqualToString:@"close"]) return 0;
  return 2;
}

/** Chỉ giữ phần tử là NSString khác rỗng - mảng từ JS có thể lẫn null/số. */
static NSArray<NSString *> *TuyaTimerIds(NSArray *raw) {
  NSMutableArray<NSString *> *out = [NSMutableArray array];
  for (id v in raw ?: @[]) {
    NSString *s = TuyaStr(v, @"");
    if (s.length > 0) [out addObject:s];
  }
  return out;
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

// Sửa MỘT timer đã có (theo timerId). inputJson giống `addTimer` nhưng KHÔNG cần taskName - timer đã
// thuộc task của nó rồi; đổi task thì phải xoá và tạo lại.
- (void)updateTimer:(NSString *)timerId
          inputJson:(NSString *)inputJson
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject {
  NSDictionary *in = TuyaJsonDict(inputJson);
  NSString *bizId = TuyaStr(in[@"bizId"], @"");
  NSString *time = TuyaStr(in[@"time"], @"");
  NSDictionary *dps = TuyaJsonDict(in[@"dpsJson"]);
  if (timerId.length == 0 || bizId.length == 0 || time.length == 0 || dps.count == 0) {
    reject(@"invalid_param", @"updateTimer cần timerId, bizId, time và dpsJson khác rỗng", nil);
    return;
  }
  [self.timer updateTimerWithTimerId:timerId
                               loops:TuyaStr(in[@"loops"], @"0000000")
                               bizId:bizId
                             bizType:TuyaBizType(in[@"bizType"])
                                time:time
                                 dps:dps
                              status:TuyaBool(in[@"status"], YES)
                           isAppPush:TuyaBool(in[@"appPush"], NO)
                           aliasName:TuyaStr(in[@"aliasName"], @"")
                             success:^{ resolve(nil); }
                             failure:^(NSError *e) { reject(@"update_timer_error", e.localizedDescription, e); }];
}

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

// Bật / tắt / xoá timer mà KHÔNG phải xoá rồi tạo lại (giữ nguyên giờ + thứ đã đặt).
// timerIds rỗng ⇒ áp dụng cho cả task (đúng hợp đồng với Android `updateCategoryTimerStatus`).
- (void)updateTimerStatus:(NSString *)taskName
                    bizId:(NSString *)bizId
                  bizType:(NSString *)bizType
                 timerIds:(NSArray *)timerIds
                       op:(NSString *)op
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  NSArray<NSString *> *ids = TuyaTimerIds(timerIds);
  NSUInteger updateType = TuyaTimerUpdateType(op);
  NSUInteger biz = TuyaBizType(bizType);
  if (bizId.length == 0) {
    reject(@"invalid_param", @"updateTimerStatus cần bizId", nil);
    return;
  }
  void (^ok)(void) = ^{ resolve(nil); };
  void (^fail)(NSError *) = ^(NSError *e) {
    reject(@"update_timer_status_error", e.localizedDescription, e);
  };

  if (ids.count == 0) {
    if (taskName.length == 0) {
      reject(@"invalid_param", @"updateTimerStatus cần taskName khi không truyền timerIds", nil);
      return;
    }
    [self.timer updateTimerTaskStatusWithTask:taskName
                                        bizId:bizId
                                      bizType:biz
                                   updateType:updateType
                                      success:ok
                                      failure:fail];
    return;
  }
  [self.timer updateTimerStatusWithTimerIds:ids
                                      bizId:bizId
                                    bizType:biz
                                 updateType:(int)updateType
                                    success:ok
                                    failure:fail];
}

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaTimerSpecJSI>(params);
}

@end
