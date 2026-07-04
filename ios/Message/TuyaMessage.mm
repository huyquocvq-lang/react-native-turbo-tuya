#import "TuyaMessage.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>
#import <ThingSmartBaseKit/ThingSmartSDK+PushNotification.h>
#import <ThingSmartMessageKit/ThingSmartMessage.h>
#import <ThingSmartMessageKit/ThingSmartMessage+ThingDeprecatedApi.h>
#import <ThingSmartMessageKit/ThingSmartMessageSetting.h>

// WIRED (iOS): message list/read/delete + push status (total + by-type, [ThingSmartSDK sharedInstance])
// + DND on/off (ThingSmartMessageSetting).
// ⚠️ Verify: get*PushStatusWithSuccess block type (ThingSuccessBOOL); typo cố hữu 'Stauts'; ThingSmartMessageSetting init
//    + selector getDeviceDNDSettingstatusSuccess: / setDeviceDNDSettingStatus:.
// Còn TODO (iOS): DND list/add/modify/remove (request model). Wire trên Xcode:
//   message badge: getLatestMessageWithSuccess:
//   push:    [ThingSmartSDK sharedInstance] deviceToken + get/setPushStatusWithStatus + get/setDevice|Family|Notice|MarketingPushStatusWithStauts (TYPO 'Stauts')
//   DND:     ThingSmartMessageSetting add/modify/remove...DNDRequestModel + getAllDNDListWithSuccess
// Verbatim: docs/research/tuya-home-sdk-message-management.md. Android wired phần push-total/DND-write/registerDevice/deleteMessages.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-message-management.md.", what],
         nil);
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

@interface TuyaMessage ()
@property (nonatomic, strong) ThingSmartMessage *message;
@end

@implementation TuyaMessage

RCT_EXPORT_MODULE()

- (ThingSmartMessage *)message {
  if (!_message) { _message = [[ThingSmartMessage alloc] init]; }
  return _message;
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
- (void)getMessageHasNew:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getMessageHasNew", reject); }

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

- (void)deleteMessagesByType:(NSString *)type
                         ids:(NSArray *)ids
                      srcIds:(NSArray *)srcIds
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject {
  NSArray<NSString *> *msgIds = TuyaStringArray(ids);
  if (msgIds.count == 0) { resolve(@YES); return; }
  ThingSmartMessageListDeleteRequestModel *req = [[ThingSmartMessageListDeleteRequestModel alloc] init];
  req.msgType = TuyaMsgTypeFromString(type);
  req.msgIds = msgIds;
  req.msgSrcIds = TuyaStringArray(srcIds);
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
  ThingSmartMessageSetting *s = [[ThingSmartMessageSetting alloc] init];
  [s getDeviceDNDSettingstatusSuccess:^(BOOL b) { resolve(@(b)); }
                              failure:^(NSError *e) { reject(@"dnd_status_error", e.localizedDescription, e); }];
}

- (void)setDndStatus:(BOOL)open
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  ThingSmartMessageSetting *s = [[ThingSmartMessageSetting alloc] init];
  [s setDeviceDNDSettingStatus:open
                       success:^{ resolve(@(open)); }
                       failure:^(NSError *e) { reject(@"dnd_status_error", e.localizedDescription, e); }];
}

- (void)getDndList:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getDndList", reject); }

- (void)getOnceDndList:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getOnceDndList", reject); }

- (void)addDnd:(NSString *)startTime
       endTime:(NSString *)endTime
         loops:(NSString *)loops
    allDevices:(BOOL)allDevices
        devIds:(NSArray *)devIds
       resolve:(RCTPromiseResolveBlock)resolve
        reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"addDnd", reject); }

- (void)addOnceDnd:(NSString *)startTime
           endTime:(NSString *)endTime
        allDevices:(BOOL)allDevices
            devIds:(NSArray *)devIds
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"addOnceDnd", reject); }

- (void)modifyDnd:(double)dndId
        startTime:(NSString *)startTime
          endTime:(NSString *)endTime
            loops:(NSString *)loops
       allDevices:(BOOL)allDevices
           devIds:(NSArray *)devIds
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"modifyDnd", reject); }

- (void)removeDnd:(double)dndId
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"removeDnd", reject); }

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaMessageSpecJSI>(params);
}

@end
