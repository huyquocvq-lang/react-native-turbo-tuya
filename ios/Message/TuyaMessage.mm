#import "TuyaMessage.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// WIRED (iOS): push status (total + by-type, [ThingSmartSDK sharedInstance]) + DND on/off (ThingSmartMessageSetting).
// ⚠️ Verify: get*PushStatusWithSuccess block type (ThingSuccessBOOL); typo cố hữu 'Stauts'; ThingSmartMessageSetting init
//    + selector getDeviceDNDSettingstatusSuccess: / setDeviceDNDSettingStatus:.
// Còn TODO (iOS): registerDevice (deviceToken NSData), message-list/detail/hasNew/read/delete (request model + bean fields),
//    DND list/add/modify/remove (request model). Wire trên Xcode:
//   message: ThingSmartMessage fetchMessageListWithListRequestModel:/fetchMessageDetailListWithListRequestModel:/
//            readMessageWithReadRequestModel:/deleteMessageWithDeleteRequestModel:/getLatestMessageWithSuccess:
//   push:    [ThingSmartSDK sharedInstance] deviceToken + get/setPushStatusWithStatus + get/setDevice|Family|Notice|MarketingPushStatusWithStauts (TYPO 'Stauts')
//   DND:     ThingSmartMessageSetting add/modify/remove...DNDRequestModel + getAllDNDListWithSuccess
// Verbatim: docs/research/tuya-home-sdk-message-management.md. Android wired phần push-total/DND-write/registerDevice/deleteMessages.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-message-management.md.", what],
         nil);
}

@implementation TuyaMessage

RCT_EXPORT_MODULE()

// ---------- Push token ----------
- (void)registerDevice:(NSString *)token
              provider:(NSString *)provider
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"registerDevice", reject); }

- (void)unregisterDevice:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"unregisterDevice", reject); }

// ---------- Message list / detail ----------
- (void)getMessageList:(double)offset
                 limit:(double)limit
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getMessageList", reject); }

- (void)getMessageListByType:(NSString *)type
                      offset:(double)offset
                       limit:(double)limit
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getMessageListByType", reject); }

- (void)getMessageDetailList:(NSString *)type
                    msgSrcId:(NSString *)msgSrcId
                      offset:(double)offset
                       limit:(double)limit
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getMessageDetailList", reject); }

// ---------- Has-new / read / delete ----------
- (void)getMessageHasNew:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getMessageHasNew", reject); }

- (void)markMessagesRead:(NSString *)type
                     ids:(NSArray *)ids
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"markMessagesRead", reject); }

- (void)deleteMessages:(NSArray *)ids
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"deleteMessages", reject); }

- (void)deleteMessagesByType:(NSString *)type
                         ids:(NSArray *)ids
                      srcIds:(NSArray *)srcIds
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"deleteMessagesByType", reject); }

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
