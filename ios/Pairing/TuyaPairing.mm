#import "TuyaPairing.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>
// ⚠️ Nếu symbol BLE thiếu khi build: thêm #import <ThingSmartBLEKit/ThingSmartBLEKit.h> (manager/blewifi activator).

// TuyaPairing (iOS) - WIRED: token + Wi-Fi EZ/AP (ThingSmartActivator delegate) + BLE scan/pair (ThingSmartBLEManager)
// + combo BLE+Wi-Fi (ThingSmartBLEWifiActivator) + auto-token. Verbatim: docs/research/tuya-home-sdk-device-pairing.md
// + tuya-home-sdk-bluetooth.md. P3 advanced (sub-device/gateway/QR/wired/destroyActivator) giữ TODO.
// Đã verify header: ThingActivatorModeEZ/AP ✓; scan type = ThingBLEScanTypeNoraml (typo nguyên văn của SDK);
// combo dùng property bleWifiDelegate + callback bleWifiActivator:didReceiveBLEWifiConfigDevice:error: ✓;
// failure của activeBLE/startConfigBLEWifi là ThingFailureHandler (block rỗng - SDK không trả NSError).
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire - xem docs/research/tuya-home-sdk-device-pairing.md.", what],
         nil);
}

static NSDictionary *TuyaPairResult(ThingSmartDeviceModel *m) {
  return @{ @"devId": m.devId ?: @"", @"name": m.name ?: @"", @"productId": m.productId ?: @"",
            @"isOnline": @(m.isOnline), @"iconUrl": m.iconUrl ?: @"" };
}

@interface TuyaPairing () <ThingSmartActivatorDelegate, ThingSmartBLEManagerDelegate, ThingSmartBLEWifiActivatorDelegate>
@property (nonatomic, copy) RCTPromiseResolveBlock wifiResolve;
@property (nonatomic, copy) RCTPromiseRejectBlock wifiReject;
@property (nonatomic, copy) RCTPromiseResolveBlock comboResolve;
@property (nonatomic, copy) RCTPromiseRejectBlock comboReject;
@property (nonatomic, strong) ThingSmartBLEWifiActivator *comboActivator;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ThingBLEAdvModel *> *scanned;
@end

@implementation TuyaPairing

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents { return @[@"onPairingProgress", @"onBleScan"]; }

- (NSMutableDictionary<NSString *, ThingBLEAdvModel *> *)scanned {
  if (!_scanned) { _scanned = [NSMutableDictionary dictionary]; }
  return _scanned;
}

// ---------- Wi-Fi token ----------
- (void)getPairingToken:(double)homeId
                resolve:(RCTPromiseResolveBlock)resolve
                 reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartActivator sharedInstance] getTokenWithHomeId:(long long)homeId
                                                   success:^(NSString *token) { resolve(token); }
                                                   failure:^(NSError *e) { reject(@"token_error", e.localizedDescription, e); }];
}

// ---------- Wi-Fi pairing (EZ/AP, kết quả qua delegate) ----------
- (void)doWifiPairingMode:(NSString *)mode
                     ssid:(NSString *)ssid
                 password:(NSString *)password
                    token:(NSString *)token
               timeoutSec:(double)timeoutSec
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  self.wifiResolve = resolve;
  self.wifiReject = reject;
  ThingActivatorMode m = [mode.uppercaseString isEqualToString:@"AP"] ? ThingActivatorModeAP : ThingActivatorModeEZ;
  [ThingSmartActivator sharedInstance].delegate = self;
  [[ThingSmartActivator sharedInstance] startConfigWiFi:m
                                                   ssid:ssid
                                               password:password
                                                  token:token
                                                timeout:timeoutSec];
}

- (void)startWifiPairing:(NSString *)mode
                    ssid:(NSString *)ssid
                password:(NSString *)password
                   token:(NSString *)token
              timeoutSec:(double)timeoutSec
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  [self doWifiPairingMode:mode ssid:ssid password:password token:token timeoutSec:timeoutSec resolve:resolve reject:reject];
}

- (void)startWifiPairingAuto:(double)homeId
                        mode:(NSString *)mode
                        ssid:(NSString *)ssid
                    password:(NSString *)password
                  timeoutSec:(double)timeoutSec
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartActivator sharedInstance] getTokenWithHomeId:(long long)homeId
                                                   success:^(NSString *token) {
    [self doWifiPairingMode:mode ssid:ssid password:password token:token timeoutSec:timeoutSec resolve:resolve reject:reject];
  } failure:^(NSError *e) { reject(@"token_error", e.localizedDescription, e); }];
}

- (void)stopWifiPairing {
  [[ThingSmartActivator sharedInstance] stopConfigWiFi];
  self.wifiResolve = nil;
  self.wifiReject = nil;
}

// ThingSmartActivatorDelegate
- (void)activator:(ThingSmartActivator *)activator
   didReceiveDevice:(ThingSmartDeviceModel *)deviceModel
              error:(NSError *)error {
  if (error) {
    if (self.wifiReject) self.wifiReject(@"pairing_error", error.localizedDescription, error);
  } else if (deviceModel) {
    if (self.wifiResolve) self.wifiResolve(TuyaPairResult(deviceModel));
  }
  self.wifiResolve = nil;
  self.wifiReject = nil;
  [activator stopConfigWiFi];
}

// Tiến trình trung gian (optional delegate) → onPairingProgress.
- (void)activator:(ThingSmartActivator *)activator
   didReceiveDevice:(ThingSmartDeviceModel *)deviceModel
               step:(ThingActivatorStep)step
              error:(NSError *)error {
  [self emit:@"onPairingProgress" body:@{ @"step": [NSString stringWithFormat:@"%ld", (long)step], @"dataJson": @"" }];
}

// ---------- BLE scan ----------
- (void)startBleScan:(double)timeoutSec {
  [ThingSmartBLEManager sharedInstance].delegate = self;
  [[ThingSmartBLEManager sharedInstance] startListeningWithType:ThingBLEScanTypeNoraml cacheStatu:YES];
}

- (void)stopBleScan {
  [[ThingSmartBLEManager sharedInstance] stopListening:YES];
}

- (void)didDiscoveryDeviceWithDeviceInfo:(ThingBLEAdvModel *)deviceInfo {
  if (deviceInfo.uuid) { self.scanned[deviceInfo.uuid] = deviceInfo; }
  [self emit:@"onBleScan" body:@{
    @"id": @"",
    @"name": @"",
    @"productId": deviceInfo.productId ?: @"",
    @"uuid": deviceInfo.uuid ?: @"",
    @"mac": deviceInfo.mac ?: @"",
    @"address": @"",
    @"deviceType": @0,
  }];
}

// ---------- BLE single pairing ----------
- (void)startBlePairing:(double)homeId
                   uuid:(NSString *)uuid
              productId:(NSString *)productId
                address:(NSString *)address
             deviceType:(double)deviceType
             timeoutSec:(double)timeoutSec
                resolve:(RCTPromiseResolveBlock)resolve
                 reject:(RCTPromiseRejectBlock)reject {
  ThingBLEAdvModel *adv = self.scanned[uuid];
  if (!adv) { reject(@"ble_scan_required", @"Chưa scan thấy uuid - gọi startBleScan() trước.", nil); return; }
  [[ThingSmartBLEManager sharedInstance] activeBLE:adv
                                            homeId:(long long)homeId
                                           success:^(ThingSmartDeviceModel *m) { resolve(TuyaPairResult(m)); }
                                           failure:^{ reject(@"ble_pairing_error", @"Ghép nối BLE thất bại (SDK không trả chi tiết lỗi).", nil); }];
}

// ---------- Combo BLE+Wi-Fi (kết quả qua delegate) ----------
- (void)startBleWifiPairing:(double)homeId
                       uuid:(NSString *)uuid
                       ssid:(NSString *)ssid
                   password:(NSString *)password
                 timeoutSec:(double)timeoutSec
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject {
  ThingBLEAdvModel *adv = self.scanned[uuid];
  if (!adv) { reject(@"ble_scan_required", @"Chưa scan thấy uuid - gọi startBleScan() trước.", nil); return; }
  self.comboResolve = resolve;
  self.comboReject = reject;
  if (!self.comboActivator) { self.comboActivator = [[ThingSmartBLEWifiActivator alloc] init]; }
  self.comboActivator.bleWifiDelegate = self;
  [self.comboActivator startConfigBLEWifiDeviceWithUUID:uuid
                                                 homeId:(long long)homeId
                                              productId:(adv.productId ?: @"")
                                                   ssid:ssid
                                               password:password
                                                timeout:timeoutSec
                                                success:^{ /* device về qua delegate */ }
                                                failure:^{
    if (self.comboReject) self.comboReject(@"combo_pairing_error", @"Ghép nối BLE+Wi-Fi thất bại (SDK không trả chi tiết lỗi).", nil);
    self.comboResolve = nil; self.comboReject = nil;
  }];
}

- (void)stopBleWifiPairing:(NSString *)uuid {
  // ThingSmartBLEWifiActivator không expose stop verbatim - gỡ delegate để bỏ callback.
  self.comboActivator.bleWifiDelegate = nil;
  self.comboResolve = nil;
  self.comboReject = nil;
}

// ThingSmartBLEWifiActivatorDelegate (tên method đã verify khớp header nguyên văn)
- (void)bleWifiActivator:(ThingSmartBLEWifiActivator *)activator
   didReceiveBLEWifiConfigDevice:(ThingSmartDeviceModel *)deviceModel
                           error:(NSError *)error {
  if (error) {
    if (self.comboReject) self.comboReject(@"combo_pairing_error", error.localizedDescription, error);
  } else if (deviceModel) {
    if (self.comboResolve) self.comboResolve(TuyaPairResult(deviceModel));
  }
  self.comboResolve = nil;
  self.comboReject = nil;
}

// ---------- P3: pairing nâng cao (unified/ThingSmartActivator - chưa verbatim) ----------
- (void)startSubDevicePairing:(NSString *)gatewayDevId timeoutSec:(double)timeoutSec {}
- (void)stopSubDevicePairing:(NSString *)gatewayDevId {}

- (void)startGatewayPairing:(NSString *)gatewayDevId
                  productId:(NSString *)productId
                      token:(NSString *)token
                 timeoutSec:(double)timeoutSec
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startGatewayPairing", reject); }

- (void)startQrPairing:(double)homeId
               assetId:(NSString *)assetId
                  code:(NSString *)code
            timeoutSec:(double)timeoutSec
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startQrPairing", reject); }

- (void)startWiredPairing:(double)homeId
                    token:(NSString *)token
               timeoutSec:(double)timeoutSec
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startWiredPairing", reject); }

- (void)destroyActivator {
  [[ThingSmartActivator sharedInstance] stopConfigWiFi];
  [ThingSmartActivator sharedInstance].delegate = nil;
  self.comboActivator.bleWifiDelegate = nil;
  self.comboActivator = nil;
  [self.scanned removeAllObjects];
}

- (void)dealloc {
  [ThingSmartActivator sharedInstance].delegate = nil;
  _comboActivator.bleWifiDelegate = nil;
}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) - không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaPairingSpecJSI>(params);
}

@end
