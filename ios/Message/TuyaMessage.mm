#import "TuyaMessage.h"

// TuyaMessage (iOS) — TODO-reject. Wire trên Xcode:
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
               reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getPushStatus", reject); }

- (void)setPushStatus:(BOOL)open
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"setPushStatus", reject); }

- (void)getPushStatusByType:(NSString *)pushType
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getPushStatusByType", reject); }

- (void)setPushStatusByType:(NSString *)pushType
                       open:(BOOL)open
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"setPushStatusByType", reject); }

// ---------- Do-Not-Disturb ----------
- (void)getDndStatus:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getDndStatus", reject); }

- (void)setDndStatus:(BOOL)open
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"setDndStatus", reject); }

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

+ (NSString *)moduleName { return @"TuyaMessage"; }

@end
