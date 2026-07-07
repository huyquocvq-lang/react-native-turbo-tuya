#import "TuyaMesh.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>
// ⚠️ Nếu thiếu symbol mesh: thêm #import <ThingSmartBLEMeshKit/...> (SIG/Tuya mesh manager).

// TuyaMesh (iOS) - WIRED best-effort theo verbatim docs/research/tuya-home-sdk-matter-mesh-ios.md (§B SIG, §C Tuya).
// Tách 2 manager theo meshType: 'sig' → ThingSmartSIGMeshManager · 'tuya' → ThingBLEMeshManager.
// ⚠️ Cần verify trên thiết bị mesh thật: name/pwd cho Tuya startScan,
//    SIG DP control (note nói publishDps trên device - ở đây dùng publishNodeId trên mesh instance cho cả 2; verify).
// ThingBleMeshDeviceModel.mac là uint32_t (đã verify header) → key dict + "mac" emit ra JS dùng chuỗi decimal,
//    JS truyền lại đúng chuỗi đó vào activateSubDevice nên round-trip khớp.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire - xem docs/research/tuya-home-sdk-matter-mesh-ios.md.", what],
         nil);
}

static NSDictionary *TuyaMeshParseDps(NSString *json) {
  NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
  id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
  return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
}

static NSString *TuyaMeshJson(id obj) {
  if (![obj isKindOfClass:[NSDictionary class]]) return @"{}";
  if (![NSJSONSerialization isValidJSONObject:obj]) return @"{}";
  NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"{}";
}

@interface TuyaMesh () <ThingSmartSIGMeshManagerDelegate, ThingBLEMeshManagerDelegate>
@property (nonatomic, strong) ThingSmartSIGMeshManager *sigManager;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ThingSmartSIGMeshDiscoverDeviceInfo *> *sigScanned; // theo mac
@property (nonatomic, strong) NSMutableDictionary<NSString *, ThingBleMeshDeviceModel *> *tuyaScanned;            // theo mac
@property (nonatomic, copy) RCTPromiseResolveBlock activateResolve;
@property (nonatomic, copy) RCTPromiseRejectBlock activateReject;
@end

@implementation TuyaMesh

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents {
  return @[@"onMeshDeviceFound", @"onMeshDpUpdate", @"onMeshStatusChanged"];
}

- (NSMutableDictionary *)sigScanned { if (!_sigScanned) _sigScanned = [NSMutableDictionary dictionary]; return _sigScanned; }
- (NSMutableDictionary *)tuyaScanned { if (!_tuyaScanned) _tuyaScanned = [NSMutableDictionary dictionary]; return _tuyaScanned; }

static BOOL TuyaIsSig(NSString *meshType) { return [meshType.lowercaseString isEqualToString:@"sig"]; }

// ---------- Create / list ----------
- (void)createSigMesh:(double)homeId
                 name:(NSString *)name
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject {
  [ThingSmartBleMesh createSIGMeshWithHomeId:(long long)homeId
                                     success:^(ThingSmartBleMeshModel *meshModel) { resolve(meshModel.meshId ?: @""); }
                                     failure:^(NSError *e) { reject(@"create_sig_mesh_error", e.localizedDescription, e); }];
}

- (void)createTuyaMesh:(double)homeId
                  name:(NSString *)name
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  [ThingSmartBleMesh createBleMeshWithMeshName:name
                                       homeId:(long long)homeId
                                      success:^(ThingSmartBleMeshModel *meshModel) { resolve(meshModel.meshId ?: @""); }
                                      failure:^(NSError *e) { reject(@"create_tuya_mesh_error", e.localizedDescription, e); }];
}

- (void)getMeshList:(double)homeId
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [ThingSmartHome homeWithHomeId:(long long)homeId];
  if (!home) { reject(@"no_home", @"Không tìm thấy home", nil); return; }
  // Gộp SIG + Tuya (2 list riêng); resolve 1 lần khi cả 2 xong; lỗi 1 loại → coi rỗng, vẫn trả loại kia.
  NSMutableArray *out = [NSMutableArray array];
  __block NSInteger pending = 2;
  void (^done)(void) = ^{ if (--pending == 0) resolve(out); };
  [home getSIGMeshListWithSuccess:^(NSArray<ThingSmartBleMeshModel *> *list) {
    for (ThingSmartBleMeshModel *m in list) {
      [out addObject:@{ @"meshId": m.meshId ?: @"", @"name": m.name ?: @"", @"type": @"sig" }];
    }
    done();
  } failure:^(NSError *e) { done(); }];
  [home getMeshListWithSuccess:^(NSArray<ThingSmartBleMeshModel *> *list) {
    for (ThingSmartBleMeshModel *m in list) {
      [out addObject:@{ @"meshId": m.meshId ?: @"", @"name": m.name ?: @"", @"type": @"tuya" }];
    }
    done();
  } failure:^(NSError *e) { done(); }];
}

// ---------- Client lifecycle ----------
- (void)startMeshClient:(double)homeId
                 meshId:(NSString *)meshId
               meshType:(NSString *)meshType
          searchTimeSec:(double)searchTimeSec {
  if (TuyaIsSig(meshType)) {
    // SIG: tìm model theo meshId rồi init manager qua ThingSmartBleMesh (+SIGMesh) - ttl mặc định 8 theo doc header.
    ThingSmartHome *home = [ThingSmartHome homeWithHomeId:(long long)homeId];
    [home getSIGMeshListWithSuccess:^(NSArray<ThingSmartBleMeshModel *> *list) {
      for (ThingSmartBleMeshModel *m in list) {
        if ([m.meshId isEqualToString:meshId]) {
          self.sigManager = [ThingSmartBleMesh initSIGMeshManager:m ttl:8 nodeIds:nil];
          self.sigManager.delegate = self;
          break;
        }
      }
    } failure:^(NSError *e) {}];
  } else {
    [ThingBLEMeshManager sharedInstance].delegate = self;
  }
}

- (void)stopMeshClient:(double)homeId meshId:(NSString *)meshId meshType:(NSString *)meshType {
  if (TuyaIsSig(meshType)) { [self.sigManager stopActiveDevice]; }
  // Tuya: doc không có stop scan rõ → no-op.
}

// ---------- Search ----------
- (void)searchSubDevices:(double)homeId
                  meshId:(NSString *)meshId
                meshType:(NSString *)meshType
              timeoutSec:(double)timeoutSec {
  if (TuyaIsSig(meshType)) {
    [self.sigManager startSearch];
  } else {
    // ⚠️ name/pwd lấy từ mesh model thật; wifiAddress/otaAddress=0 cho non-gateway.
    [[ThingBLEMeshManager sharedInstance] startScanWithName:meshId pwd:@"" active:YES wifiAddress:0 otaAddress:0];
  }
}

// ---------- Activate ----------
- (void)activateSubDevice:(double)homeId
                   meshId:(NSString *)meshId
                 meshType:(NSString *)meshType
                      mac:(NSString *)mac
               timeoutSec:(double)timeoutSec
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  self.activateResolve = resolve;
  self.activateReject = reject;
  if (TuyaIsSig(meshType)) {
    ThingSmartSIGMeshDiscoverDeviceInfo *info = self.sigScanned[mac];
    if (!info) { reject(@"mesh_scan_required", @"Chưa scan thấy mac - gọi searchSubDevices trước.", nil); return; }
    [self.sigManager startActive:@[info]];
  } else {
    ThingBleMeshDeviceModel *dev = self.tuyaScanned[mac];
    if (!dev) { reject(@"mesh_scan_required", @"Chưa scan thấy mac - gọi searchSubDevices trước.", nil); return; }
    [[ThingBLEMeshManager sharedInstance] activeMeshDevice:dev];
  }
}

// ---------- DP control (mesh instance) ----------
- (void)publishMeshDps:(double)homeId
                meshId:(NSString *)meshId
              meshType:(NSString *)meshType
                nodeId:(NSString *)nodeId
                   pcc:(NSString *)pcc
               dpsJson:(NSString *)dpsJson
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  ThingSmartBleMesh *mesh = [ThingSmartBleMesh bleMeshWithMeshId:meshId homeId:(long long)homeId];
  if (!mesh) { reject(@"no_mesh", @"Không tìm thấy mesh", nil); return; }
  [mesh publishNodeId:nodeId pcc:pcc dps:TuyaMeshParseDps(dpsJson)
              success:^{ resolve(nil); }
              failure:^(NSError *e) { reject(@"publish_mesh_dps_error", e.localizedDescription, e); }];
}

- (void)multicastMeshDps:(double)homeId
                  meshId:(NSString *)meshId
                meshType:(NSString *)meshType
                 localId:(NSString *)localId
                     pcc:(NSString *)pcc
                 dpsJson:(NSString *)dpsJson
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  ThingSmartBleMesh *mesh = [ThingSmartBleMesh bleMeshWithMeshId:meshId homeId:(long long)homeId];
  if (!mesh) { reject(@"no_mesh", @"Không tìm thấy mesh", nil); return; }
  [mesh multiPublishWithLocalId:localId pcc:pcc dps:TuyaMeshParseDps(dpsJson)
                        success:^{ resolve(nil); }
                        failure:^(NSError *e) { reject(@"multicast_mesh_dps_error", e.localizedDescription, e); }];
}

// ---------- SIG delegate ----------
- (void)sigMeshManager:(ThingSmartSIGMeshManager *)manager didScanedDevice:(ThingSmartSIGMeshDiscoverDeviceInfo *)device {
  if (device.mac) { self.sigScanned[device.mac] = device; }
  [self emit:@"onMeshDeviceFound" body:@{ @"dataJson": TuyaMeshJson(@{ @"mac": device.mac ?: @"" }) }];
}

- (void)sigMeshManager:(ThingSmartSIGMeshManager *)manager
    didActiveSubDevice:(ThingSmartSIGMeshDiscoverDeviceInfo *)device
                 devId:(NSString *)devId error:(NSError *)error {
  if (error) { if (self.activateReject) self.activateReject(@"mesh_active_error", error.localizedDescription, error); }
  else { if (self.activateResolve) self.activateResolve(@{ @"devId": devId ?: @"", @"name": @"", @"productId": @"", @"nodeId": @"" }); }
  self.activateResolve = nil; self.activateReject = nil;
}

- (void)sigMeshManager:(ThingSmartSIGMeshManager *)manager
 didFailToActiveDevice:(ThingSmartSIGMeshDiscoverDeviceInfo *)device error:(NSError *)error {
  if (self.activateReject) self.activateReject(@"mesh_active_error", error.localizedDescription, error);
  self.activateResolve = nil; self.activateReject = nil;
}

// ---------- Tuya delegate ----------
- (void)bleMeshManager:(ThingBLEMeshManager *)manager didScanedDevice:(ThingBleMeshDeviceModel *)device {
  NSString *macKey = [NSString stringWithFormat:@"%u", device.mac];
  if (device.mac) { self.tuyaScanned[macKey] = device; }
  [self emit:@"onMeshDeviceFound" body:@{ @"dataJson": TuyaMeshJson(@{ @"mac": macKey }) }];
}

- (void)activeDeviceSuccessWithName:(NSString *)name deviceId:(NSString *)deviceId error:(NSError *)error {
  if (error) { if (self.activateReject) self.activateReject(@"mesh_active_error", error.localizedDescription, error); }
  else { if (self.activateResolve) self.activateResolve(@{ @"devId": deviceId ?: @"", @"name": name ?: @"", @"productId": @"", @"nodeId": @"" }); }
  self.activateResolve = nil; self.activateReject = nil;
}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) - không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaMeshSpecJSI>(params);
}

@end
