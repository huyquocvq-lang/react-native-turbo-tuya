#import "TuyaMesh.h"
#import "TuyaReject.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>
// ⚠️ Nếu thiếu symbol mesh: thêm #import <ThingSmartBLEMeshKit/...> (SIG/Tuya mesh manager).

// TuyaMesh (iOS) - WIRED best-effort theo verbatim docs/research/tuya-home-sdk-matter-mesh-ios.md (§B SIG, §C Tuya).
// Tách 2 manager theo meshType: 'sig' → ThingSmartSIGMeshManager · 'tuya' → ThingBLEMeshManager.
// Review lại theo header Pods (ThingSmartBLEMeshKit 5.13.5) + sample chính chủ (SIGMeshTableViewController):
//   SIG : initSIGMeshManager:ttl:nodeIds: → delegate → startSearch (header: vừa scan thiết bị chưa pair, vừa TỰ
//         connect node đã pair = "client") → startActive:@[info] → didActiveSubDevice / didFailToActiveDevice.
//   Tuya: [ThingSmartUser sharedInstance].meshModel/.mesh = mesh của home (SDK active thiết bị VÀO mesh này);
//         connect mesh: startScanWithName:<code> pwd:<password> active:NO ; scan thiết bị chưa pair: tên mặc định
//         kInitMeshName ("out_of_mesh") + mật khẩu mặc định "123456", active:YES (trước đây truyền meshId/"" → sai).
//   searchTimeSec (startMeshClient) không có tương đương iOS → bỏ qua. onMeshDpUpdate/onMeshStatusChanged chưa phát
//   trên iOS (DP sub-device về qua ThingSmartDevice delegate - TuyaDevice.onDeviceStatus).
// ⚠️ Cần verify trên thiết bị mesh thật: SIG DP control (note nói publishDps trên device - ở đây dùng publishNodeId
//    trên mesh instance cho cả 2; verify).
// ThingBleMeshDeviceModel.mac là uint32_t (đã verify header) → key dict + "mac" emit ra JS dùng chuỗi decimal,
//    JS truyền lại đúng chuỗi đó vào activateSubDevice nên round-trip khớp.
static NSString *const kTuyaMeshUnpairedPwd = @"123456"; // đi cặp với kInitMeshName (@"out_of_mesh")

static NSDictionary *TuyaMeshParseDps(NSString *json) {
  NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
  id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
  return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static NSString *TuyaMeshJson(id obj) {
  if (![obj isKindOfClass:[NSDictionary class]]) return @"{}";
  if (![NSJSONSerialization isValidJSONObject:obj]) return @"{}";
  NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"{}";
}

// Reject mang mã lỗi Tuya THẬT (NSError.code + message nguyên văn) - trước đây literal làm mất mã SDK.
static void TuyaMeshReject(RCTPromiseRejectBlock reject, NSError *error, NSString *fallbackCode, NSString *fallbackMessage) {
  if (error) {
    TuyaRejectWithDomain(reject, [@(error.code) stringValue], error.localizedDescription, @"sdk");
  } else {
    TuyaRejectWithDomain(reject, fallbackCode, fallbackMessage, @"sdk");
  }
}

// State chỉ đụng trên main (methodQueue = main) → callback SDK lỡ về thread khác thì nhảy về main.
static void TuyaMeshOnMain(dispatch_block_t block) {
  if ([NSThread isMainThread]) { block(); } else { dispatch_async(dispatch_get_main_queue(), block); }
}

static ThingSmartBleMeshModel *TuyaMeshFind(NSArray<ThingSmartBleMeshModel *> *list, NSString *meshId) {
  for (ThingSmartBleMeshModel *m in list) {
    if ([m.meshId isEqualToString:meshId]) return m;
  }
  return nil;
}

// Kết quả active: lấy name/productId/nodeId từ cache thiết bị (nodeId cần cho publishMeshDps).
static NSDictionary *TuyaMeshSubDevice(NSString *devId, NSString *fallbackName) {
  ThingSmartDeviceModel *m = devId.length ? [ThingSmartDevice deviceWithDeviceId:devId].deviceModel : nil;
  return @{ @"devId": devId ?: @"",
            @"name": m.name.length ? m.name : (fallbackName ?: @""),
            @"productId": m.productId ?: @"",
            @"nodeId": m.nodeId ?: @"" };
}

@interface TuyaMesh () <ThingSmartSIGMeshManagerDelegate, ThingBLEMeshManagerDelegate>
@property (nonatomic, strong) ThingSmartSIGMeshManager *sigManager;
@property (nonatomic, copy) NSString *sigMeshId;                                                                   // mesh của sigManager
@property (nonatomic, strong) NSMutableDictionary<NSString *, ThingSmartSIGMeshDiscoverDeviceInfo *> *sigScanned; // theo mac
@property (nonatomic, strong) NSMutableDictionary<NSString *, ThingBleMeshDeviceModel *> *tuyaScanned;            // theo mac
@property (nonatomic, copy) RCTPromiseResolveBlock activateResolve;
@property (nonatomic, copy) RCTPromiseRejectBlock activateReject;
@property (nonatomic, assign) NSUInteger activateGen;
@property (nonatomic, assign) NSUInteger scanGen;
@end

@implementation TuyaMesh

RCT_EXPORT_MODULE()

// SDK gọi delegate trên main → chạy method trên main luôn để dict scan/promise không bị race.
- (dispatch_queue_t)methodQueue { return dispatch_get_main_queue(); }

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
  // SDK không nhận tên cho SIG mesh → `name` bị bỏ qua (giống Android).
  [ThingSmartBleMesh createSIGMeshWithHomeId:(long long)homeId
                                     success:^(ThingSmartBleMeshModel *meshModel) { resolve(meshModel.meshId ?: @""); }
                                     failure:^(NSError *e) {
    TuyaMeshReject(reject, e, @"create_sig_mesh_error", @"Create SIG mesh failed.");
  }];
}

- (void)createTuyaMesh:(double)homeId
                  name:(NSString *)name
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  [ThingSmartBleMesh createBleMeshWithMeshName:name
                                       homeId:(long long)homeId
                                      success:^(ThingSmartBleMeshModel *meshModel) { resolve(meshModel.meshId ?: @""); }
                                      failure:^(NSError *e) {
    TuyaMeshReject(reject, e, @"create_tuya_mesh_error", @"Create Tuya mesh failed.");
  }];
}

- (void)getMeshList:(double)homeId
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [ThingSmartHome homeWithHomeId:(long long)homeId];
  if (!home) { TuyaRejectWithDomain(reject, @"no_home", @"Không tìm thấy home", @"sdk"); return; }
  // Gộp SIG + Tuya (2 list riêng); resolve 1 lần khi cả 2 xong; lỗi 1 loại → vẫn trả loại kia;
  // lỗi CẢ 2 → reject mã thật (ưu tiên SIG) thay vì nuốt thành mảng rỗng.
  NSMutableArray *out = [NSMutableArray array];
  __block NSInteger pending = 2;
  __block NSError *sigError = nil;
  __block NSError *tuyaError = nil;
  __block NSInteger failures = 0;
  void (^done)(void) = ^{
    if (--pending > 0) return;
    if (failures == 2) { TuyaMeshReject(reject, sigError ?: tuyaError, @"mesh_list_error", @"Get mesh list failed."); }
    else { resolve(out); }
  };
  [home getSIGMeshListWithSuccess:^(NSArray<ThingSmartBleMeshModel *> *list) {
    TuyaMeshOnMain(^{
      for (ThingSmartBleMeshModel *m in list) {
        [out addObject:@{ @"meshId": m.meshId ?: @"", @"name": m.name ?: @"", @"type": @"sig" }];
      }
      done();
    });
  } failure:^(NSError *e) { TuyaMeshOnMain(^{ sigError = e; failures++; done(); }); }];
  [home getMeshListWithSuccess:^(NSArray<ThingSmartBleMeshModel *> *list) {
    TuyaMeshOnMain(^{
      for (ThingSmartBleMeshModel *m in list) {
        [out addObject:@{ @"meshId": m.meshId ?: @"", @"name": m.name ?: @"", @"type": @"tuya" }];
      }
      done();
    });
  } failure:^(NSError *e) { TuyaMeshOnMain(^{ tuyaError = e; failures++; done(); }); }];
}

// ---------- Mesh context ----------
// SIG: manager theo meshId (tạo 1 lần, tái dùng) - ttl mặc định 8 theo doc header.
- (void)withSigManager:(double)homeId
                meshId:(NSString *)meshId
            completion:(void (^)(ThingSmartSIGMeshManager *manager, NSError *error))completion {
  if (self.sigManager && [self.sigMeshId isEqualToString:meshId]) {
    self.sigManager.delegate = self;
    completion(self.sigManager, nil);
    return;
  }
  ThingSmartHome *home = [ThingSmartHome homeWithHomeId:(long long)homeId];
  if (!home) { completion(nil, nil); return; }
  [home getSIGMeshListWithSuccess:^(NSArray<ThingSmartBleMeshModel *> *list) {
    TuyaMeshOnMain(^{
      ThingSmartBleMeshModel *m = TuyaMeshFind(list, meshId);
      ThingSmartSIGMeshManager *mgr = m ? [ThingSmartBleMesh initSIGMeshManager:m ttl:8 nodeIds:nil] : nil;
      if (mgr) {
        mgr.delegate = self;
        self.sigManager = mgr;
        self.sigMeshId = meshId;
      }
      completion(mgr, nil);
    });
  } failure:^(NSError *e) { TuyaMeshOnMain(^{ completion(nil, e); }); }];
}

// Tuya: SDK lấy mesh đích từ ThingSmartUser (meshModel + mesh) → set theo meshId trước khi connect/active.
- (void)withTuyaMesh:(double)homeId
              meshId:(NSString *)meshId
          completion:(void (^)(ThingSmartBleMeshModel *model, NSError *error))completion {
  ThingSmartUser *user = [ThingSmartUser sharedInstance];
  if ([user.meshModel.meshId isEqualToString:meshId] && user.mesh) {
    [ThingBLEMeshManager sharedInstance].delegate = self;
    completion(user.meshModel, nil);
    return;
  }
  ThingSmartHome *home = [ThingSmartHome homeWithHomeId:(long long)homeId];
  if (!home) { completion(nil, nil); return; }
  [home getMeshListWithSuccess:^(NSArray<ThingSmartBleMeshModel *> *list) {
    TuyaMeshOnMain(^{
      ThingSmartBleMeshModel *m = TuyaMeshFind(list, meshId);
      if (m) {
        user.meshModel = m;
        user.mesh = [ThingSmartBleMesh bleMeshWithMeshId:m.meshId homeId:(long long)homeId];
        [ThingBLEMeshManager sharedInstance].delegate = self;
      }
      completion(m, nil);
    });
  } failure:^(NSError *e) { TuyaMeshOnMain(^{ completion(nil, e); }); }];
}

// ---------- Client lifecycle ----------
- (void)startMeshClient:(double)homeId
                 meshId:(NSString *)meshId
               meshType:(NSString *)meshType
          searchTimeSec:(double)searchTimeSec {
  if (TuyaIsSig(meshType)) {
    [self withSigManager:homeId meshId:meshId completion:^(ThingSmartSIGMeshManager *manager, NSError *error) {
      [manager startSearch]; // node đã active được tự connect (header) - trước đây chỉ init, không connect
    }];
  } else {
    [self withTuyaMesh:homeId meshId:meshId completion:^(ThingSmartBleMeshModel *model, NSError *error) {
      if (!model) return;
      self.scanGen++;
      [[ThingBLEMeshManager sharedInstance] startScanWithName:model.code ?: @""
                                                          pwd:model.password ?: @""
                                                       active:NO
                                                  wifiAddress:0
                                                   otaAddress:0];
    }];
  }
}

- (void)stopMeshClient:(double)homeId meshId:(NSString *)meshId meshType:(NSString *)meshType {
  self.scanGen++;
  if (TuyaIsSig(meshType)) {
    [self.sigManager stopActiveDevice];
    [self.sigManager stopSerachDevice]; // (typo "Serach" nguyên văn header)
  } else {
    [[ThingBLEMeshManager sharedInstance] stopActiveDevice];
    [[ThingBLEMeshManager sharedInstance] stopScan];
  }
  [self settleActivate:nil error:nil code:@"mesh_active_cancelled" message:@"Mesh client stopped during activation."];
}

// ---------- Search ----------
- (void)searchSubDevices:(double)homeId
                  meshId:(NSString *)meshId
                meshType:(NSString *)meshType
              timeoutSec:(double)timeoutSec {
  NSUInteger gen = ++self.scanGen;
  BOOL sig = TuyaIsSig(meshType);
  if (sig) {
    [self.sigScanned removeAllObjects];
    // Trước đây gọi thẳng [self.sigManager startSearch] - manager chưa kịp tạo (startMeshClient async) → im lặng.
    [self withSigManager:homeId meshId:meshId completion:^(ThingSmartSIGMeshManager *manager, NSError *error) {
      if (gen == self.scanGen) [manager startSearch];
    }];
  } else {
    [self.tuyaScanned removeAllObjects];
    [ThingBLEMeshManager sharedInstance].delegate = self;
    [[ThingBLEMeshManager sharedInstance] startScanWithName:kInitMeshName
                                                        pwd:kTuyaMeshUnpairedPwd
                                                     active:YES
                                                wifiAddress:0
                                                 otaAddress:0];
  }
  if (timeoutSec > 0) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSec * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (gen != self.scanGen) return;
      if (sig) { [self.sigManager stopSerachDevice]; }
      else { [[ThingBLEMeshManager sharedInstance] stopScan]; }
    });
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
  BOOL sig = TuyaIsSig(meshType);
  ThingSmartSIGMeshDiscoverDeviceInfo *info = sig ? self.sigScanned[mac] : nil;
  ThingBleMeshDeviceModel *dev = sig ? nil : self.tuyaScanned[mac];
  if (!info && !dev) {
    TuyaRejectWithDomain(reject, @"mesh_scan_required", @"Chưa scan thấy mac - gọi searchSubDevices trước.", @"sdk");
    return;
  }
  // Promise cũ còn treo → reject rõ ràng (trước đây bị ghi đè, JS chờ mãi).
  [self settleActivate:nil error:nil code:@"mesh_superseded"
               message:@"activateSubDevice was called again before the previous call finished."];
  NSUInteger gen = ++self.activateGen;
  self.activateResolve = resolve;
  self.activateReject = reject;
  self.scanGen++; // dừng hẹn giờ stop-scan cũ (không cắt ngang lúc đang active)

  if (sig) {
    [self withSigManager:homeId meshId:meshId completion:^(ThingSmartSIGMeshManager *manager, NSError *error) {
      if (gen != self.activateGen) return;
      if (!manager) {
        [self settleActivate:nil error:error code:@"mesh_not_found"
                     message:[NSString stringWithFormat:@"SIG mesh %@ not found in home.", meshId]];
        return;
      }
      [manager startActive:@[info]];
    }];
  } else {
    [self withTuyaMesh:homeId meshId:meshId completion:^(ThingSmartBleMeshModel *model, NSError *error) {
      if (gen != self.activateGen) return;
      if (!model) {
        [self settleActivate:nil error:error code:@"mesh_not_found"
                     message:[NSString stringWithFormat:@"Tuya mesh %@ not found in home.", meshId]];
        return;
      }
      [[ThingBLEMeshManager sharedInstance] activeMeshDevice:dev];
    }];
  }

  // Header không có timeout cho startActive:/activeMeshDevice: → tự chốt để promise không treo.
  NSTimeInterval timeout = timeoutSec > 0 ? timeoutSec : 100;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (gen != self.activateGen || !self.activateReject) return;
    if (sig) { [self.sigManager stopActiveDevice]; }
    else { [[ThingBLEMeshManager sharedInstance] stopActiveDevice]; }
    [self settleActivate:nil error:nil code:@"mesh_active_timeout"
                 message:[NSString stringWithFormat:@"Mesh activation did not finish within %.0fs.", timeout]];
  });
}

- (void)settleActivate:(NSDictionary *)result error:(NSError *)error code:(NSString *)code message:(NSString *)message {
  RCTPromiseResolveBlock res = self.activateResolve;
  RCTPromiseRejectBlock rej = self.activateReject;
  self.activateResolve = nil;
  self.activateReject = nil;
  if (!res || !rej) return;
  if (result) { res(result); } else { TuyaMeshReject(rej, error, code, message); }
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
  NSDictionary *dps = TuyaMeshParseDps(dpsJson);
  if (!dps) { TuyaRejectWithDomain(reject, @"invalid_dps_json", @"dpsJson must be a JSON object string.", @"sdk"); return; }
  ThingSmartBleMesh *mesh = [ThingSmartBleMesh bleMeshWithMeshId:meshId homeId:(long long)homeId];
  if (!mesh) { TuyaRejectWithDomain(reject, @"no_mesh", @"Không tìm thấy mesh", @"sdk"); return; }
  [mesh publishNodeId:nodeId pcc:pcc dps:dps
              success:^{ resolve(nil); }
              failure:^(NSError *e) { TuyaMeshReject(reject, e, @"publish_mesh_dps_error", @"Publish mesh DPs failed."); }];
}

- (void)multicastMeshDps:(double)homeId
                  meshId:(NSString *)meshId
                meshType:(NSString *)meshType
                 localId:(NSString *)localId
                     pcc:(NSString *)pcc
                 dpsJson:(NSString *)dpsJson
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  NSDictionary *dps = TuyaMeshParseDps(dpsJson);
  if (!dps) { TuyaRejectWithDomain(reject, @"invalid_dps_json", @"dpsJson must be a JSON object string.", @"sdk"); return; }
  ThingSmartBleMesh *mesh = [ThingSmartBleMesh bleMeshWithMeshId:meshId homeId:(long long)homeId];
  if (!mesh) { TuyaRejectWithDomain(reject, @"no_mesh", @"Không tìm thấy mesh", @"sdk"); return; }
  [mesh multiPublishWithLocalId:localId pcc:pcc dps:dps
                        success:^{ resolve(nil); }
                        failure:^(NSError *e) { TuyaMeshReject(reject, e, @"multicast_mesh_dps_error", @"Multicast mesh DPs failed."); }];
}

// ---------- SIG delegate ----------
- (void)sigMeshManager:(ThingSmartSIGMeshManager *)manager didScanedDevice:(ThingSmartSIGMeshDiscoverDeviceInfo *)device {
  TuyaMeshOnMain(^{
    if (device.mac.length) { self.sigScanned[device.mac] = device; }
    [self emit:@"onMeshDeviceFound" body:@{ @"dataJson": TuyaMeshJson(@{ @"mac": device.mac ?: @"",
                                                                           @"meshType": @"sig",
                                                                           @"productId": device.productId ?: @"" }) }];
  });
}

- (void)sigMeshManager:(ThingSmartSIGMeshManager *)manager
    didActiveSubDevice:(ThingSmartSIGMeshDiscoverDeviceInfo *)device
                 devId:(NSString *)devId error:(NSError *)error {
  TuyaMeshOnMain(^{
    if (error) { [self settleActivate:nil error:error code:@"mesh_active_error" message:@"Mesh activation failed."]; }
    else { [self settleActivate:TuyaMeshSubDevice(devId, nil) error:nil code:nil message:nil]; }
  });
}

- (void)sigMeshManager:(ThingSmartSIGMeshManager *)manager
 didFailToActiveDevice:(ThingSmartSIGMeshDiscoverDeviceInfo *)device error:(NSError *)error {
  TuyaMeshOnMain(^{ [self settleActivate:nil error:error code:@"mesh_active_error" message:@"Mesh activation failed."]; });
}

// Chung selector cho SIG + Tuya. Thứ tự finish/result không được header đảm bảo → chờ 3s rồi mới coi là thất bại.
- (void)didFinishToActiveDevList {
  TuyaMeshOnMain(^{
    NSUInteger gen = self.activateGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      if (gen != self.activateGen) return;
      [self settleActivate:nil error:nil code:@"mesh_active_error" message:@"Activation finished without a result."];
    });
  });
}

- (void)didFinishToActiveDevList:(ThingSmartSIGMeshManager *)manager { [self didFinishToActiveDevList]; }

// ---------- Tuya delegate ----------
- (void)bleMeshManager:(ThingBLEMeshManager *)manager didScanedDevice:(ThingBleMeshDeviceModel *)device {
  TuyaMeshOnMain(^{
    NSString *macKey = [NSString stringWithFormat:@"%u", device.mac];
    if (device.mac) { self.tuyaScanned[macKey] = device; }
    [self emit:@"onMeshDeviceFound" body:@{ @"dataJson": TuyaMeshJson(@{ @"mac": macKey,
                                                                           @"meshType": @"tuya",
                                                                           @"name": device.name ?: @"",
                                                                           @"productId": device.productId ?: @"" }) }];
  });
}

- (void)activeDeviceSuccessWithName:(NSString *)name deviceId:(NSString *)deviceId error:(NSError *)error {
  TuyaMeshOnMain(^{
    if (error) { [self settleActivate:nil error:error code:@"mesh_active_error" message:@"Mesh activation failed."]; }
    else { [self settleActivate:TuyaMeshSubDevice(deviceId, name) error:nil code:nil message:nil]; }
  });
}

- (void)bleMeshManager:(ThingBLEMeshManager *)manager
    didActiveSubDevice:(ThingBleMeshDeviceModel *)device
                 devId:(NSString *)devId
                 error:(NSError *)error {
  TuyaMeshOnMain(^{
    if (error) { [self settleActivate:nil error:error code:@"mesh_active_error" message:@"Mesh activation failed."]; }
    else { [self settleActivate:TuyaMeshSubDevice(devId, device.name) error:nil code:nil message:nil]; }
  });
}

- (void)bleMeshManager:(ThingBLEMeshManager *)manager didFailToActiveDevice:(ThingBleMeshDeviceModel *)device error:(NSError *)error {
  TuyaMeshOnMain(^{ [self settleActivate:nil error:error code:@"mesh_active_error" message:@"Mesh activation failed."]; });
}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) - không khai lại.

- (void)invalidate {
  self.scanGen++;
  self.activateGen++;
  self.activateResolve = nil;
  self.activateReject = nil;
  if (self.sigManager) {
    [self.sigManager stopActiveDevice];
    [self.sigManager stopSerachDevice];
    if (self.sigManager.delegate == self) self.sigManager.delegate = nil;
  }
  ThingBLEMeshManager *tuya = [ThingBLEMeshManager sharedInstance];
  if (tuya.delegate == self) {
    [tuya stopActiveDevice];
    [tuya stopScan];
    tuya.delegate = nil;
  }
  [super invalidate];
}

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaMeshSpecJSI>(params);
}

@end
