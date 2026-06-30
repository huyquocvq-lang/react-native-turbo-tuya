#import "TuyaMesh.h"

// TuyaMesh (iOS) — SKELETON TODO-reject. iOS SIG/Tuya mesh signature CHƯA verbatim (note "Câu hỏi mở"):
// SIG: ThingSmartSIGMeshManager / ThingSmartSIGMeshDevice (create qua ThingSmartHome createSIGMesh..., control publishDps:);
// Tuya: ThingSmartBleMesh family. Mở đúng trang iOS mesh reference khi wire. Verbatim: docs/research/tuya-home-sdk-bluetooth.md §7/§8.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-bluetooth.md §7/§8.", what],
         nil);
}

@implementation TuyaMesh

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents {
  return @[@"onMeshDeviceFound", @"onMeshDpUpdate", @"onMeshStatusChanged"];
}

- (void)createSigMesh:(double)homeId
                 name:(NSString *)name
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"createSigMesh", reject); }

- (void)createTuyaMesh:(double)homeId
                  name:(NSString *)name
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"createTuyaMesh", reject); }

- (void)getMeshList:(double)homeId
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getMeshList", reject); }

- (void)startMeshClient:(NSString *)meshId searchTimeSec:(double)searchTimeSec {}
- (void)stopMeshClient:(NSString *)meshId {}
- (void)searchSubDevices:(NSString *)meshId timeoutSec:(double)timeoutSec {}

- (void)activateSubDevice:(NSString *)meshId
                      mac:(NSString *)mac
               timeoutSec:(double)timeoutSec
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"activateSubDevice", reject); }

- (void)publishMeshDps:(NSString *)meshId
                nodeId:(NSString *)nodeId
                   pcc:(NSString *)pcc
               dpsJson:(NSString *)dpsJson
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"publishMeshDps", reject); }

- (void)multicastMeshDps:(NSString *)meshId
                 localId:(NSString *)localId
                     pcc:(NSString *)pcc
                 dpsJson:(NSString *)dpsJson
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"multicastMeshDps", reject); }

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) — không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaMeshSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaMesh"; }

@end
