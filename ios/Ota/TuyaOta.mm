#import "TuyaOta.h"

// TuyaOta (iOS) — TODO-reject (impl bằng ThingSmartDevice checkFirmwareUpgrade/startFirmwareUpgrade +
// ThingSmartDeviceDelegate firmwareUpgradeProgress/otaUpdateStatusChanged trên Xcode; selector verbatim ở note).
// Android wired đầy đủ. Event onOtaProgress/onOtaStatusChanged/onOtaSuccess/onOtaFailure phát qua TuyaEventEmitter.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-device-management.md (OTA).", what],
         nil);
}

@implementation TuyaOta

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents {
  return @[@"onOtaProgress", @"onOtaStatusChanged", @"onOtaSuccess", @"onOtaFailure"];
}

- (void)checkFirmwareUpgrade:(NSString *)devId
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"checkFirmwareUpgrade", reject); }

- (void)startFirmwareUpgrade:(NSString *)devId
                       types:(NSArray *)types
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startFirmwareUpgrade", reject); }

- (void)cancelFirmwareUpgrade:(NSString *)devId
                      otaType:(double)otaType
                      resolve:(RCTPromiseResolveBlock)resolve
                       reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"cancelFirmwareUpgrade", reject); }

- (void)confirmWarningUpgrade:(NSString *)devId
                   isContinue:(BOOL)isContinue
                      resolve:(RCTPromiseResolveBlock)resolve
                       reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"confirmWarningUpgrade", reject); }

- (void)getAutoUpgradeSwitch:(NSString *)devId
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getAutoUpgradeSwitch", reject); }

- (void)setAutoUpgradeSwitch:(NSString *)devId
                       state:(double)state
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"setAutoUpgradeSwitch", reject); }

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter).

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaOtaSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaOta"; }

@end
