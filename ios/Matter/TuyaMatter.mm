#import "TuyaMatter.h"

// TuyaMatter (iOS) - SKELETON TODO-reject. iOS dùng API HỢP NHẤT ThingSmartActivatorDiscovery (KHÁC Android dedicated)
// → spec parseSetupCode/connectDevice/commissionDevice LỆCH flow iOS (search→startActive). Cần chỉnh spec trước khi wire sạch.
// Prereq iOS: + setMatterConfigKey:(appGroupId) + entitlement matter.allow-setup-payload + Bonjour + is_matter_support.
// Verbatim iOS (intended-call) ở docs/research/tuya-home-sdk-matter-mesh-ios.md §A:
//   token: [ThingSmartActivator getTokenWithHomeId:success:failure:]
//   parse: [discovery parseSetupCode:(NSString*)] → ThingSmartActivatorDeviceModel (GIỮ)
//   discover: registerWithActivatorList:@[ThingSmartActivatorTypeMatterModel] → loadConfig → setupDelegate: → startSearch:
//   commission: startActive:(typeMatterModel{token,ssid,password,spaceId,timeout}) deviceList:@[deviceModel]
//   delegate: matterCommissioningSessionEstablishmentComplete: / matterDeviceAttestation:error:
//   attestation: continueCommissioningDevice:ignoreAttestationFailure:error: ; stop: stopActive:clearCache:
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire - xem docs/research/tuya-home-sdk-device-pairing.md §5.", what],
         nil);
}

@implementation TuyaMatter

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents {
  return @[@"onMatterDeviceFound", @"onMatterAttestation", @"onMatterError"];
}

- (void)parseSetupCode:(NSString *)code
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"parseSetupCode", reject); }

- (void)connectDevice:(double)homeId
           timeoutSec:(double)timeoutSec
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"connectDevice", reject); }

- (void)commissionDevice:(double)homeId
                   token:(NSString *)token
                    ssid:(NSString *)ssid
                password:(NSString *)password
              timeoutSec:(double)timeoutSec
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"commissionDevice", reject); }

- (void)startDiscovery {}
- (void)stopDiscovery {}
- (void)continueCommissioning:(BOOL)ignoreAttestationFailure {}
- (void)cancelActivator {}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) - không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaMatterSpecJSI>(params);
}

@end
