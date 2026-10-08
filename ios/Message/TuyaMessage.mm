#import "TuyaMessage.h"
#import "TuyaReject.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>
#import <ThingSmartBaseKit/ThingSmartSDK+PushNotification.h>
#import <ThingSmartMessageKit/ThingSmartMessage.h>
#import <ThingSmartMessageKit/ThingSmartMessage+ThingDeprecatedApi.h>
#import <ThingSmartMessageKit/ThingSmartMessageSetting.h>

// WIRED (iOS) toàn bộ spec - verify trên Pods thật (header + disassemble ThingSmartMessageKit/BaseKit):
//   message list/detail/read/delete (ThingSmartMessage) + has-new (getLatestMessageWithSuccess: = thing.m.msg.new v1.0,
//   cùng API Android requestMessageNew) + push status (total + by-type, [ThingSmartSDK sharedInstance]; typo 'Stauts')
//   + DND (ThingSmartMessageSetting).
// DND - cùng API cloud với Android 7.5.6:
//   recurring = thing.m.device.alarm.nodisturb.{list,add,update,remove} v1.0 · startTime/endTime 'HH:mm', loops 7 ký tự.
//   once      = m.message.device.alarm.nodisturb.{list,add,update} v3.0 · 'YYYY-MM-DD HH:mm', loops cố định "0000000".
//   devIds gửi lên = chuỗi JSON {"devIds":[..],"allDevIds":bool}; list trả dict thô, devIds = chuỗi JSON array.
//   addDnd/addOnceDnd: SDK nuốt timerId → gọi cùng API qua ThingSmartRequest (xem TuyaDndAdd).

static NSString *const kTuyaOnceLoops = @"0000000";

// Reject mang mã lỗi Tuya THẬT (shape { code, message, domain } - TuyaReject.h): mã cloud nằm ở
// userInfo[NSLocalizedFailureReasonErrorKey] (ThingSmartRequest.h; = errorCode bên Android), không có thì NSError.code.
static void TuyaRejectError(RCTPromiseRejectBlock reject, NSError *error, NSString *fallbackCode) {
  id reason = error.userInfo[NSLocalizedFailureReasonErrorKey];
  NSString *code = fallbackCode;
  if ([reason isKindOfClass:[NSString class]] && [(NSString *)reason length] > 0) {
    code = (NSString *)reason;
  } else if ([reason isKindOfClass:[NSNumber class]]) {
    code = [(NSNumber *)reason stringValue];
  } else if (error) {
    code = [@(error.code) stringValue];
  }
  TuyaRejectWithDomain(reject, code, error.localizedDescription ?: @"Tuya SDK returned no error details.", @"sdk");
}

static ThingMessageType TuyaMsgTypeFromString(NSString *type) {
  NSString *t = type.lowercaseString ?: @"";
  if ([t isEqualToString:@"alarm"]) return ThingMessageTypeAlarm;
  if ([t isEqualToString:@"family"]) return ThingMessageTypeFamily;
  return ThingMessageTypeNotice;
}

static NSString *TuyaMsgTypeString(NSInteger value) {
  if (value == ThingMessageTypeAlarm || value == 4) return @"alarm";
  if (value == ThingMessageTypeFamily) return @"family";
  return @"notification";
}

static NSArray<NSString *> *TuyaStringArray(NSArray *values) {
  NSMutableArray<NSString *> *out = [NSMutableArray array];
  for (id value in values ?: @[]) {
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
      [out addObject:(NSString *)value];
    }
  }
  return out;
}

// Đọc an toàn từ dict JSON thô (NSNull / kiểu lạ → giá trị rỗng, không crash).
static NSString *TuyaStr(id v) {
  if ([v isKindOfClass:[NSString class]]) return (NSString *)v;
  if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
  return @"";
}

static long long TuyaLongLong(id v) {
  return ([v isKindOfClass:[NSNumber class]] || [v isKindOfClass:[NSString class]]) ? [v longLongValue] : 0;
}

static BOOL TuyaBool(id v) {
  return ([v isKindOfClass:[NSNumber class]] || [v isKindOfClass:[NSString class]]) ? [v boolValue] : NO;
}

static NSData *TuyaDataFromHex(NSString *hex) {
  NSMutableString *clean = [NSMutableString stringWithString:hex ?: @""];
  for (NSString *s in @[@"<", @">", @" ", @"-", @"\n", @"\t"]) {
    [clean replaceOccurrencesOfString:s withString:@"" options:0 range:NSMakeRange(0, clean.length)];
  }
  if (clean.length == 0 || clean.length % 2 != 0) return nil;

  NSMutableData *data = [NSMutableData dataWithCapacity:clean.length / 2];
  for (NSUInteger i = 0; i < clean.length; i += 2) {
    NSString *byteString = [clean substringWithRange:NSMakeRange(i, 2)];
    unsigned int byte = 0;
    NSScanner *scanner = [NSScanner scannerWithString:byteString];
    if (![scanner scanHexInt:&byte] || !scanner.isAtEnd) return nil;
    UInt8 value = (UInt8)byte;
    [data appendBytes:&value length:1];
  }
  return data;
}

static NSDictionary *TuyaMessageMap(ThingSmartMessageListModel *m, NSString *fallbackType) {
  NSString *msgType = fallbackType.length > 0 ? fallbackType : TuyaMsgTypeString(m.msgType);
  return @{
    @"id": m.msgId ?: @"",
    @"msgType": msgType ?: @"notification",
    @"msgSrcId": m.msgSrcId ?: @"",
    @"title": m.msgTypeContent ?: @"",
    @"content": m.msgContent ?: @"",
    @"typeContent": m.msgTypeContent ?: @"",
    @"icon": m.icon ?: @"",
    @"dateTime": m.dateTime ?: @"",
    @"hasNotRead": @(m.hasNotRead),
  };
}

static NSDictionary *TuyaMessagePage(NSArray<ThingSmartMessageListModel *> *list,
                                     NSInteger offset,
                                     NSInteger limit,
                                     NSString *fallbackType) {
  NSMutableArray *items = [NSMutableArray array];
  for (ThingSmartMessageListModel *m in list ?: @[]) {
    [items addObject:TuyaMessageMap(m, fallbackType)];
  }
  return @{
    @"list": items,
    @"offset": @(offset),
    @"limit": @(limit),
    @"hasMore": @((NSInteger)items.count >= limit),
  };
}

// ---------- DND helpers ----------
static BOOL TuyaDndIsOnce(NSString *loops) {
  return loops.length == 0 || [loops isEqualToString:kTuyaOnceLoops];
}

// devIds đúng format SDK gửi (disassemble ThingSmartMessageSetting): {"devIds":[..],"allDevIds":bool}.
// omitEmptyIds: addOnceDNDWithRequestModel: bỏ key devIds khi rỗng.
static NSString *TuyaDndDevIdsJSON(BOOL allDevices, NSArray<NSString *> *devIds, BOOL omitEmptyIds) {
  NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObject:@(allDevices) forKey:@"allDevIds"];
  if (!(omitEmptyIds && devIds.count == 0)) payload[@"devIds"] = devIds ?: @[];
  NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";
}

// devIds trong list = chuỗi JSON array (ThingSmartMessageDNDTimerModel parse bằng NSJSONSerialization);
// phòng hờ mảng / object {"devIds":[..]} / chuỗi phân cách dấu phẩy.
static NSArray<NSString *> *TuyaDndDevIds(id raw) {
  if ([raw isKindOfClass:[NSArray class]]) return TuyaStringArray(raw);
  if ([raw isKindOfClass:[NSDictionary class]]) {
    id inner = ((NSDictionary *)raw)[@"devIds"];
    return [inner isKindOfClass:[NSArray class]] ? TuyaStringArray(inner) : @[];
  }
  if (![raw isKindOfClass:[NSString class]]) return @[];
  NSString *s = [(NSString *)raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (s.length == 0) return @[];
  if ([s hasPrefix:@"["] || [s hasPrefix:@"{"]) {
    id json = [NSJSONSerialization JSONObjectWithData:[s dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if ([json isKindOfClass:[NSArray class]] || [json isKindOfClass:[NSDictionary class]]) return TuyaDndDevIds(json);
  }
  NSCharacterSet *trim = [NSCharacterSet characterSetWithCharactersInString:@" \"\n\t"];
  NSMutableArray<NSString *> *out = [NSMutableArray array];
  for (NSString *part in [s componentsSeparatedByString:@","]) {
    NSString *t = [part stringByTrimmingCharactersInSet:trim];
    if (t.length > 0) [out addObject:t];
  }
  return out;
}

// Dict thô (getDNDListSuccess:/getAllDNDList onceDNDList) hoặc ThingSmartMessageDNDTimerModel → TuyaDndPeriod.
// Dùng dict thô thay vì *ModelList: model parse devIds bằng NSJSONSerialization (devIds nil → exception).
static NSDictionary *TuyaDndPeriod(id item) {
  long long timerId = 0;
  NSString *start = @"", *end = @"", *loops = @"";
  BOOL all = NO;
  NSArray<NSString *> *ids = @[];
  if ([item isKindOfClass:[ThingSmartMessageDNDTimerModel class]]) {
    ThingSmartMessageDNDTimerModel *m = (ThingSmartMessageDNDTimerModel *)item;
    timerId = m.timerId;
    start = TuyaStr(m.startTime);
    end = TuyaStr(m.endTime);
    loops = TuyaStr(m.loops);
    all = m.allDevIds;
    ids = TuyaDndDevIds(m.devIds);
  } else if ([item isKindOfClass:[NSDictionary class]]) {
    NSDictionary *d = (NSDictionary *)item;
    timerId = TuyaLongLong(d[@"id"]);
    start = TuyaStr(d[@"startTime"]);
    end = TuyaStr(d[@"endTime"]);
    loops = TuyaStr(d[@"loops"]);
    all = TuyaBool(d[@"allDevIds"]);
    ids = TuyaDndDevIds(d[@"devIds"]);
  } else {
    return nil;
  }
  return @{
    @"id": @(timerId),
    @"startTime": start,
    @"endTime": end,
    @"loops": TuyaDndIsOnce(loops) ? @"" : loops,
    @"allDevices": @(all),
    @"devIds": ids,
  };
}

// once=NO: bỏ entry loops "0000000" (phòng hờ list v1 lẫn once); once=YES: onceDNDList SDK đã tách sẵn.
static NSArray *TuyaDndPeriods(id list, BOOL once) {
  NSMutableArray *out = [NSMutableArray array];
  for (id item in ([list isKindOfClass:[NSArray class]] ? (NSArray *)list : @[])) {
    NSDictionary *p = TuyaDndPeriod(item);
    if (p && ([(NSString *)p[@"loops"] length] == 0) == once) [out addObject:p];
  }
  return out;
}

static long long TuyaDndTimerId(id result) {
  if ([result isKindOfClass:[NSDictionary class]]) {
    NSDictionary *d = (NSDictionary *)result;
    return TuyaLongLong(d[@"id"] ?: d[@"timerId"]);
  }
  return TuyaLongLong(result);
}

// SDK iOS addDNDWithDNDRequestModel:/addOnceDNDWithRequestModel: nhận timerId từ server nhưng success là
// ThingSuccessHandler (bỏ mất id). Gửi CHÍNH request đó (api/version/postData lấy từ disassemble ThingSmartMessageKit;
// Android addDNDWithStartTime/addOnceDNDWithStartTime gọi cùng API và trả Long) qua ThingSmartRequest public để có timerId.
static void TuyaDndAdd(ThingSmartRequest *request,
                       NSString *api,
                       NSString *version,
                       NSDictionary *postData,
                       RCTPromiseResolveBlock resolve,
                       RCTPromiseRejectBlock reject) {
  [request requestWithApiName:api
                     postData:postData
                      version:version
                      success:^(id result) { resolve(@(TuyaDndTimerId(result))); }
                      failure:^(NSError *e) { TuyaRejectError(reject, e, @"add_dnd_error"); }];
}

@interface TuyaMessage ()
@property (nonatomic, strong) ThingSmartMessage *message;
@property (nonatomic, strong) ThingSmartMessageSetting *dndSetting;
@property (nonatomic, strong) ThingSmartRequest *dndRequest;
@end

@implementation TuyaMessage

RCT_EXPORT_MODULE()

- (ThingSmartMessage *)message {
  if (!_message) { _message = [[ThingSmartMessage alloc] init]; }
  return _message;
}

- (ThingSmartMessageSetting *)dndSetting {
  if (!_dndSetting) { _dndSetting = [[ThingSmartMessageSetting alloc] init]; }
  return _dndSetting;
}

- (ThingSmartRequest *)dndRequest {
  if (!_dndRequest) { _dndRequest = [[ThingSmartRequest alloc] init]; }
  return _dndRequest;
}

// ---------- Push token ----------
- (void)registerDevice:(NSString *)token
              provider:(NSString *)provider
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  if (![provider.lowercaseString isEqualToString:@"apns"]) {
    reject(@"unsupported_provider", @"iOS registerDevice expects APNs token provider 'apns'.", nil);
    return;
  }
  NSData *deviceToken = TuyaDataFromHex(token);
  if (!deviceToken) {
    reject(@"invalid_apns_token", @"APNs token không hợp lệ.", nil);
    return;
  }
  [[ThingSmartSDK sharedInstance] setDeviceToken:deviceToken
                                       withError:nil
                                         success:^(__unused id result) { resolve(nil); }
                                         failure:^(NSError *e) { reject(@"register_device_error", e.localizedDescription, e); }];
}

- (void)unregisterDevice:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartSDK sharedInstance] setDeviceToken:nil
                                       withError:nil
                                         success:^(__unused id result) { resolve(nil); }
                                         failure:^(NSError *e) { reject(@"unregister_device_error", e.localizedDescription, e); }];
}

// ---------- Message list / detail ----------
- (void)getMessageList:(double)offset
                 limit:(double)limit
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  NSInteger off = MAX(0, (NSInteger)offset);
  NSInteger lim = MAX(1, (NSInteger)limit);
  ThingSmartMessageListRequestModelV1 *req = [[ThingSmartMessageListRequestModelV1 alloc] init];
  req.offset = off;
  req.limit = lim;
  [self.message fetchMessageListWithRequestModel:req
                                         success:^(NSArray<ThingSmartMessageListModel *> *messageList) {
    resolve(TuyaMessagePage(messageList, off, lim, nil));
  } failure:^(NSError *e) { reject(@"get_message_list_error", e.localizedDescription, e); }];
}

- (void)getMessageListByType:(NSString *)type
                      offset:(double)offset
                       limit:(double)limit
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject {
  NSInteger off = MAX(0, (NSInteger)offset);
  NSInteger lim = MAX(1, (NSInteger)limit);
  NSString *normalizedType = TuyaMsgTypeString(TuyaMsgTypeFromString(type));
  ThingSmartMessageListRequestModel *req = [[ThingSmartMessageListRequestModel alloc] init];
  req.msgType = TuyaMsgTypeFromString(type);
  req.offset = off;
  req.limit = lim;
  [self.message fetchMessageListWithListRequestModel:req
                                             success:^(NSArray<ThingSmartMessageListModel *> *messageList) {
    resolve(TuyaMessagePage(messageList, off, lim, normalizedType));
  } failure:^(NSError *e) { reject(@"get_message_list_error", e.localizedDescription, e); }];
}

- (void)getMessageDetailList:(NSString *)type
                    msgSrcId:(NSString *)msgSrcId
                      offset:(double)offset
                       limit:(double)limit
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject {
  NSInteger off = MAX(0, (NSInteger)offset);
  NSInteger lim = MAX(1, (NSInteger)limit);
  NSString *normalizedType = TuyaMsgTypeString(TuyaMsgTypeFromString(type));
  ThingSmartMessageDetailListRequestModel *req = [[ThingSmartMessageDetailListRequestModel alloc] init];
  req.msgType = TuyaMsgTypeFromString(type);
  req.msgSrcId = msgSrcId ?: @"";
  req.offset = off;
  req.limit = lim;
  [self.message fetchMessageDetailListWithListRequestModel:req
                                                   success:^(NSArray<ThingSmartMessageListModel *> *messageList) {
    resolve(TuyaMessagePage(messageList, off, lim, normalizedType));
  } failure:^(NSError *e) { reject(@"get_message_detail_error", e.localizedDescription, e); }];
}

// ---------- Has-new / read / delete ----------
// getLatestMessageWithSuccess: = thing.m.msg.new v1.0 (disassemble ThingMessageService), trả dict thô
// {alarm, family, notification} - cùng API/payload Android requestMessageNew (MessageHasNew).
- (void)getMessageHasNew:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  [self.message getLatestMessageWithSuccess:^(NSDictionary *dict) {
    NSDictionary *d = [dict isKindOfClass:[NSDictionary class]] ? dict : @{};
    resolve(@{
      @"alarm": @(TuyaBool(d[@"alarm"])),
      @"family": @(TuyaBool(d[@"family"])),
      @"notification": @(TuyaBool(d[@"notification"])),
    });
  } failure:^(NSError *e) { TuyaRejectError(reject, e, @"get_message_has_new_error"); }];
}

- (void)markMessagesRead:(NSString *)type
                     ids:(NSArray *)ids
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  NSArray<NSString *> *msgIds = TuyaStringArray(ids);
  if (msgIds.count == 0) { resolve(@YES); return; }
  ThingSmartMessageListReadRequestModel *req = [[ThingSmartMessageListReadRequestModel alloc] init];
  req.msgType = TuyaMsgTypeFromString(type);
  req.msgIds = msgIds;
  [self.message readMessageWithReadRequestModel:req
                                        success:^(BOOL result) { resolve(@(result)); }
                                        failure:^(NSError *e) { reject(@"mark_message_read_error", e.localizedDescription, e); }];
}

- (void)deleteMessages:(NSArray *)ids
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  NSArray<NSString *> *msgIds = TuyaStringArray(ids);
  if (msgIds.count == 0) { resolve(@YES); return; }
  // Generic delete in the JS surface only has ids. Tuya's new iOS delete API needs msgType/srcIds,
  // so use the old all-type helper here and keep the typed delete API below for precise calls.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  [self.message deleteMessage:msgIds
                      success:^{ resolve(@YES); }
                      failure:^(NSError *e) { reject(@"delete_messages_error", e.localizedDescription, e); }];
#pragma clang diagnostic pop
}

// Docs Tuya: srcIds = xoá cả nhóm alarm theo thiết bị, ids = xoá từng tin chi tiết → chỉ no-op khi CẢ HAI rỗng
// (SDK gửi ids/msgSrcIds dạng chuỗi nối dấu phẩy, mảng rỗng → "").
- (void)deleteMessagesByType:(NSString *)type
                         ids:(NSArray *)ids
                      srcIds:(NSArray *)srcIds
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject {
  NSArray<NSString *> *msgIds = TuyaStringArray(ids);
  NSArray<NSString *> *msgSrcIds = TuyaStringArray(srcIds);
  if (msgIds.count == 0 && msgSrcIds.count == 0) { resolve(@YES); return; }
  ThingSmartMessageListDeleteRequestModel *req = [[ThingSmartMessageListDeleteRequestModel alloc] init];
  req.msgType = TuyaMsgTypeFromString(type);
  req.msgIds = msgIds;
  req.msgSrcIds = msgSrcIds;
  [self.message deleteMessageWithDeleteRequestModel:req
                                            success:^(BOOL result) { resolve(@(result)); }
                                            failure:^(NSError *e) { reject(@"delete_messages_error", e.localizedDescription, e); }];
}

// ---------- Push status ----------
- (void)getPushStatus:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartSDK sharedInstance] getPushStatusWithSuccess:^(BOOL b) { resolve(@(b)); }
                                                   failure:^(NSError *e) { reject(@"push_status_error", e.localizedDescription, e); }];
}

- (void)setPushStatus:(BOOL)open
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartSDK sharedInstance] setPushStatusWithStatus:open
                                                  success:^{ resolve(@(open)); }
                                                  failure:^(NSError *e) { reject(@"push_status_error", e.localizedDescription, e); }];
}

// thing.m.msg.notice.switch.status / .setting: type 0 device(alarm) · 1 family · 2 notice · 4 marketing.
- (void)getPushStatusByType:(NSString *)pushType
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject {
  ThingSmartSDK *sdk = [ThingSmartSDK sharedInstance];
  NSString *t = pushType.lowercaseString;
  void (^ok)(BOOL) = ^(BOOL b) { resolve(@(b)); };
  void (^fail)(NSError *) = ^(NSError *e) { reject(@"push_status_error", e.localizedDescription, e); };
  if ([t isEqualToString:@"family"]) { [sdk getFamilyPushStatusWithSuccess:ok failure:fail]; }
  else if ([t isEqualToString:@"notification"]) { [sdk getNoticePushStatusWithSuccess:ok failure:fail]; }
  else if ([t isEqualToString:@"marketing"]) { [sdk getMarketingPushStatusWithSuccess:ok failure:fail]; }
  else { [sdk getDevicePushStatusWithSuccess:ok failure:fail]; } // 'alarm'
}

- (void)setPushStatusByType:(NSString *)pushType
                       open:(BOOL)open
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject {
  ThingSmartSDK *sdk = [ThingSmartSDK sharedInstance];
  NSString *t = pushType.lowercaseString;
  void (^ok)(void) = ^{ resolve(@(open)); };
  void (^fail)(NSError *) = ^(NSError *e) { reject(@"push_status_error", e.localizedDescription, e); };
  // Tuya iOS typo cố hữu: 'Stauts'.
  if ([t isEqualToString:@"family"]) { [sdk setFamilyPushStatusWithStauts:open success:ok failure:fail]; }
  else if ([t isEqualToString:@"notification"]) { [sdk setNoticePushStatusWithStauts:open success:ok failure:fail]; }
  else if ([t isEqualToString:@"marketing"]) { [sdk setMarketingPushStatusWithStauts:open success:ok failure:fail]; }
  else { [sdk setDevicePushStatusWithStauts:open success:ok failure:fail]; } // 'alarm'
}

// ---------- Do-Not-Disturb ----------
- (void)getDndStatus:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  [self.dndSetting getDeviceDNDSettingstatusSuccess:^(BOOL b) { resolve(@(b)); }
                                            failure:^(NSError *e) { reject(@"dnd_status_error", e.localizedDescription, e); }];
}

- (void)setDndStatus:(BOOL)open
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  [self.dndSetting setDeviceDNDSettingStatus:open
                                     success:^{ resolve(@(open)); }
                                     failure:^(NSError *e) { reject(@"dnd_status_error", e.localizedDescription, e); }];
}

// thing.m.device.alarm.nodisturb.list v1.0 (= Android getDNDList) → mảng dict thô.
- (void)getDndList:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject {
  [self.dndSetting getDNDListSuccess:^(NSArray *list) { resolve(TuyaDndPeriods(list, NO)); }
                             failure:^(NSError *e) { TuyaRejectError(reject, e, @"get_dnd_list_error"); }];
}

// m.message.device.alarm.nodisturb.list v3.0; SDK tách onceDNDList theo loops "0000000" (= Android getOnceDNDList).
- (void)getOnceDndList:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  [self.dndSetting getAllDNDListWithSuccess:^(ThingSmartMessageDNDListEntity *result) {
    resolve(TuyaDndPeriods(result.onceDNDList, YES));
  } failure:^(NSError *e) { TuyaRejectError(reject, e, @"get_dnd_list_error"); }];
}

- (void)addDnd:(NSString *)startTime
       endTime:(NSString *)endTime
         loops:(NSString *)loops
    allDevices:(BOOL)allDevices
        devIds:(NSArray *)devIds
       resolve:(RCTPromiseResolveBlock)resolve
        reject:(RCTPromiseRejectBlock)reject {
  // loops rỗng/"0000000" = DND một lần → entry lạc sang getOnceDndList. Chặn sớm như Android.
  if (TuyaDndIsOnce(loops)) {
    TuyaRejectWithDomain(reject, @"invalid_param",
        @"addDnd needs a weekly loops pattern (7 chars, at least one day set); use addOnceDnd for a one-time period.",
        @"sdk");
    return;
  }
  // = addDNDWithDNDRequestModel: (postData y hệt SDK).
  NSDictionary *postData = @{
    @"startTime": startTime ?: @"",
    @"endTime": endTime ?: @"",
    @"devIds": TuyaDndDevIdsJSON(allDevices, TuyaStringArray(devIds), NO),
    @"loops": loops,
  };
  TuyaDndAdd(self.dndRequest, @"thing.m.device.alarm.nodisturb.add", @"1.0", postData, resolve, reject);
}

- (void)addOnceDnd:(NSString *)startTime
           endTime:(NSString *)endTime
        allDevices:(BOOL)allDevices
            devIds:(NSArray *)devIds
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject {
  // = addOnceDNDWithRequestModel: (postData y hệt SDK: loops "0000000", noDisturbType 1, dpIds/dpValues "[]").
  NSDictionary *postData = @{
    @"startTime": startTime ?: @"",
    @"endTime": endTime ?: @"",
    @"loops": kTuyaOnceLoops,
    @"noDisturbType": @1,
    @"dpIds": @"[]",
    @"dpValues": @"[]",
    @"devIds": TuyaDndDevIdsJSON(allDevices, TuyaStringArray(devIds), YES),
  };
  TuyaDndAdd(self.dndRequest, @"m.message.device.alarm.nodisturb.add", @"3.0", postData, resolve, reject);
}

// loops '' | "0000000" → modifyOnceDNDWithTimerID (v3); còn lại → modifyDNDWithTimerID (v1). Giống Android.
- (void)modifyDnd:(double)dndId
        startTime:(NSString *)startTime
          endTime:(NSString *)endTime
            loops:(NSString *)loops
       allDevices:(BOOL)allDevices
           devIds:(NSArray *)devIds
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject {
  NSArray<NSString *> *ids = TuyaStringArray(devIds); // SDK dựng dict có devIDs → không được nil
  void (^ok)(void) = ^{ resolve(@YES); };
  void (^fail)(NSError *) = ^(NSError *e) { TuyaRejectError(reject, e, @"modify_dnd_error"); };
  if (TuyaDndIsOnce(loops)) {
    ThingSmartMessageOnceDNDRequestModel *req = [[ThingSmartMessageOnceDNDRequestModel alloc] init];
    req.startTime = startTime ?: @"";
    req.endTime = endTime ?: @"";
    req.devIDs = ids;
    req.isAllDevIDs = allDevices;
    [self.dndSetting modifyOnceDNDWithTimerID:(long)dndId requestModel:req success:ok failure:fail];
    return;
  }
  ThingSmartMessageSettingDNDRequestModel *req = [[ThingSmartMessageSettingDNDRequestModel alloc] init];
  req.startTime = startTime ?: @"";
  req.endTime = endTime ?: @"";
  req.devIDs = ids;
  req.isAllDevIDs = allDevices;
  // loops (deprecated) giữ nguyên chuỗi như Android; setDNDDaysWithFlags: đi vòng qua bitmask.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  req.loops = loops;
#pragma clang diagnostic pop
  [self.dndSetting modifyDNDWithTimerID:(long)dndId DNDRequestModel:req success:ok failure:fail];
}

// thing.m.device.alarm.nodisturb.remove - SDK chỉ có 1 API xoá, dùng cho cả recurring lẫn once.
- (void)removeDnd:(double)dndId
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject {
  [self.dndSetting removeDNDWithTimerID:(long)dndId
                                success:^{ resolve(@YES); }
                                failure:^(NSError *e) { TuyaRejectError(reject, e, @"remove_dnd_error"); }];
}

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaMessageSpecJSI>(params);
}

@end
