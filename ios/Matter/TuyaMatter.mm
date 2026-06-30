#import "TuyaMatter.h"

// TuyaMatter (iOS) — SKELETON TODO-reject. Matter cần: entitlement `matter.allow-setup-payload`, Bonjour trong
// Info.plist, `is_matter_support=true`, App Group (setMatterConfigKey). Wire trên Xcode (ThingSmartMatterActivator +
// ThingSmartActivatorDiscovery): parseSetupCode: / connect+commission / startSearch:+startActive: / continueCommissioningDevice:.
// Verbatim/đối chiếu: docs/research/tuya-home-sdk-device-pairing.md §5 + §4 (iOS Matter).
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-device-pairing.md §5.", what],
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

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) — không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaMatterSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaMatter"; }

@end
