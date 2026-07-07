#import "TuyaOta.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaOta (iOS) - WIRED: checkFirmwareUpgrade / startFirmwareUpgrade (fetch+filter theo type) / cancelFirmwareUpgrade
// + progress qua ThingSmartDeviceDelegate (firmwareUpgradeProgress / otaUpdateStatusChanged) → onOtaProgress/onOtaStatusChanged.
// Verbatim: docs/research/tuya-home-sdk-device-management.md (OTA iOS).
// TODO (selector iOS chưa verbatim): confirmWarningUpgrade, get/setAutoUpgradeSwitch.
// ⚠️ Verify: property của ThingSmartFirmwareUpgradeModel / ThingSmartFirmwareUpgradeStatusModel.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire - xem docs/research/tuya-home-sdk-device-management.md (OTA).", what],
         nil);
}

static NSDictionary *TuyaUpgradeInfo(ThingSmartFirmwareUpgradeModel *m) {
  return @{
    @"type": @(m.type),
    @"typeDesc": m.typeDesc ?: @"",
    @"currentVersion": m.currentVersion ?: @"",
    @"version": m.version ?: @"",
    @"upgradeStatus": @(m.upgradeStatus),
    @"upgradeType": @(m.upgradeType),
    @"fileSize": m.fileSize ?: @"",
    @"controlType": @(m.controlType),
    @"canUpgrade": @(m.upgradeStatus == 1),
    @"desc": m.desc ?: @"",
  };
}

@interface TuyaOta () <ThingSmartDeviceDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSString *, ThingSmartDevice *> *otaDevices;
@end

@implementation TuyaOta

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents {
  return @[@"onOtaProgress", @"onOtaStatusChanged", @"onOtaSuccess", @"onOtaFailure"];
}

- (NSMutableDictionary<NSString *, ThingSmartDevice *> *)otaDevices {
  if (!_otaDevices) { _otaDevices = [NSMutableDictionary dictionary]; }
  return _otaDevices;
}

// Giữ device + delegate để nhận progress trong suốt OTA.
- (ThingSmartDevice *)bindDevice:(NSString *)devId {
  ThingSmartDevice *dev = self.otaDevices[devId] ?: [ThingSmartDevice deviceWithDeviceId:devId];
  if (dev) { dev.delegate = self; self.otaDevices[devId] = dev; }
  return dev;
}

- (void)checkFirmwareUpgrade:(NSString *)devId
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { reject(@"no_device", @"Không tìm thấy thiết bị", nil); return; }
  [dev checkFirmwareUpgrade:^(NSArray<ThingSmartFirmwareUpgradeModel *> *firmwares) {
    NSMutableArray *out = [NSMutableArray array];
    for (ThingSmartFirmwareUpgradeModel *m in firmwares) { [out addObject:TuyaUpgradeInfo(m)]; }
    resolve(out);
  } failure:^(NSError *e) { reject(@"check_ota_error", e.localizedDescription, e); }];
}

- (void)startFirmwareUpgrade:(NSString *)devId
                       types:(NSArray *)types
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [self bindDevice:devId];
  if (!dev) { reject(@"no_device", @"Không tìm thấy thiết bị", nil); return; }
  // iOS startFirmwareUpgrade nhận MODEL (không phải type) → fetch list, lọc theo types (rỗng = tất cả).
  [dev checkFirmwareUpgrade:^(NSArray<ThingSmartFirmwareUpgradeModel *> *firmwares) {
    NSMutableArray<ThingSmartFirmwareUpgradeModel *> *sel = [NSMutableArray array];
    for (ThingSmartFirmwareUpgradeModel *m in firmwares) {
      if (types.count == 0 || [types containsObject:@(m.type)]) { [sel addObject:m]; }
    }
    [dev startFirmwareUpgrade:sel];
    resolve(nil); // kết quả về qua delegate
  } failure:^(NSError *e) { reject(@"start_ota_error", e.localizedDescription, e); }];
}

- (void)cancelFirmwareUpgrade:(NSString *)devId
                      otaType:(double)otaType
                      resolve:(RCTPromiseResolveBlock)resolve
                       reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { reject(@"no_device", @"Không tìm thấy thiết bị", nil); return; }
  // iOS cancel không nhận otaType (huỷ chung).
  [dev cancelFirmwareUpgrade:^{ resolve(nil); }
                     failure:^(NSError *e) { reject(@"cancel_ota_error", e.localizedDescription, e); }];
}

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

// ---------- ThingSmartDeviceDelegate (OTA gộp chung) ----------
- (void)device:(ThingSmartDevice *)device firmwareUpgradeProgress:(NSInteger)type progress:(double)progress {
  [self emit:@"onOtaProgress" body:@{ @"devId": device.deviceModel.devId ?: @"",
                                      @"type": @(type), @"progress": @(progress) }];
}

- (void)device:(ThingSmartDevice *)device otaUpdateStatusChanged:(ThingSmartFirmwareUpgradeStatusModel *)statusModel {
  // ⚠️ property statusModel (type/upgradeStatus) cần verify; success/failure để JS suy theo status.
  [self emit:@"onOtaStatusChanged" body:@{ @"devId": device.deviceModel.devId ?: @"",
                                           @"type": @(statusModel.type),
                                           @"status": @(statusModel.upgradeStatus) }];
}

- (void)dealloc {
  for (ThingSmartDevice *dev in _otaDevices.allValues) { dev.delegate = nil; }
}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter).

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaOtaSpecJSI>(params);
}

@end
