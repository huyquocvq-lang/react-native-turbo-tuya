#import "TuyaPairing.h"
#import "TuyaReject.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>
// ⚠️ Nếu symbol BLE thiếu khi build: thêm #import <ThingSmartBLEKit/ThingSmartBLEKit.h> (manager/blewifi activator).

// TuyaPairing (iOS) - WIRED: token + Wi-Fi EZ/AP (ThingSmartActivator delegate) + BLE scan/pair (ThingSmartBLEManager)
// + combo BLE+Wi-Fi (ThingSmartBLEWifiActivator) + auto-token. Verbatim: docs/research/tuya-home-sdk-device-pairing.md
// + tuya-home-sdk-bluetooth.md. P3 advanced (sub-device/gateway/QR/wired/destroyActivator) giữ TODO.
// Đã verify header: ThingActivatorModeEZ/AP ✓; scan type = ThingBLEScanTypeNoraml (typo nguyên văn của SDK);
// combo dùng property bleWifiDelegate + callback bleWifiActivator:didReceiveBLEWifiConfigDevice:error: ✓;
// failure của activeBLE/startConfigBLEWifi là ThingFailureHandler (block rỗng - SDK không trả NSError).
//
// LỖI: mọi reject đi qua TuyaReject.h → shape { code, message, domain } khớp src/errors.ts.
// Trước đây reject bằng literal (@"pairing_error") làm MẤT NSError.code (mã Tuya thật) và nuốt message
// → app chỉ hiện "[sdk:pairing_error] Unknown error." Xem dev-workflow/m1-fix-wifi-pairing/.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  TuyaRejectWithDomain(reject, @"ios_todo",
      [NSString stringWithFormat:@"iOS '%@' chưa wire - xem docs/research/tuya-home-sdk-device-pairing.md.", what],
      @"sdk");
}

// Reject mang mã lỗi Tuya THẬT: NSError.code (vd -55 = token hết hạn) + localizedDescription nguyên văn.
// SDK không trả NSError (một số ThingFailureHandler là block rỗng) → dùng fallback, nói rõ là SDK không có chi tiết.
static void TuyaRejectNSError(RCTPromiseRejectBlock reject,
                              NSError *error,
                              NSString *fallbackCode,
                              NSString *fallbackMessage) {
  if (error) {
    TuyaRejectWithDomain(reject, [@(error.code) stringValue], error.localizedDescription, @"sdk");
  } else {
    TuyaRejectWithDomain(reject, fallbackCode, fallbackMessage, @"sdk");
  }
}

static NSDictionary *TuyaPairResult(ThingSmartDeviceModel *m) {
  return @{ @"devId": m.devId ?: @"", @"name": m.name ?: @"", @"productId": m.productId ?: @"",
            @"isOnline": @(m.isOnline), @"iconUrl": m.iconUrl ?: @"" };
}

// bleType (ThingSmartBLEType, header ThingBLEAdvModel.h) có cần Wi-Fi credentials không (= combo).
// Combo (phải gửi SSID/pwd): BLEWifi(4) · BLEWifiSecurity(6) · BLEWifiPlugPlay(7) · BLELTESecurity(9) ·
// BLEWifiPriorBLE(11). Còn lại (BLE/BLEPlus/BLESecurity/BLEZigbee/BLEBeacon/Unknow) = BLE thuần, pair thẳng.
// Bảng route lấy từ sample chính chủ (DualModel vs BLEModel). Xem tuya-ios-sample-pairing-comparison.md.
static BOOL TuyaBleTypeIsCombo(ThingSmartBLEType t) {
  switch (t) {
    case ThingSmartBLETypeBLEWifi:
    case ThingSmartBLETypeBLEWifiSecurity:
    case ThingSmartBLETypeBLEWifiPlugPlay:
    case ThingSmartBLETypeBLELTESecurity:
    case ThingSmartBLETypeBLEWifiPriorBLE:
      return YES;
    default:
      return NO;
  }
}

// ThingActivatorStep → tên có nghĩa. Giá trị lấy VERBATIM từ header SDK
// (Pods/ThingSmartPairingCoreKit/.../ThingSmartPairingHeader.h) - doc Tuya KHÔNG liệt kê enum này.
// ⚠️ step 4 = TimeOut là LỖI, không phải tiến trình. JS phải phân biệt (đừng nhích checklist).
static NSString *TuyaActivatorStepName(ThingActivatorStep step) {
  switch (step) {
    case ThingActivatorStepFound:          return @"device_found";
    case ThingActivatorStepRegisted:       return @"device_registered";
    case ThingActivatorStepIntialized:     return @"device_initialized";
    case ThingActivatorStepTimeOut:        return @"device_timeout";
    case ThingActivatorStepStartDialUp:    return @"gateway_dialup_start";
    case ThingActivatorStepConnectSuccess: return @"gateway_connect_success";
  }
  return [NSString stringWithFormat:@"step_%lu", (unsigned long)step];
}

@interface TuyaPairing () <ThingSmartActivatorDelegate, ThingSmartBLEManagerDelegate, ThingSmartBLEWifiActivatorDelegate>
- (void)startApWithMode:(ThingActivatorMode)mode
                   ssid:(NSString *)ssid
               password:(NSString *)password
                  token:(NSString *)token
                regInfo:(nullable NSDictionary *)regInfo
                timeout:(double)timeoutSec;
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
                                                   failure:^(NSError *e) {
    TuyaRejectNSError(reject, e, @"token_error", @"Không lấy được pairing token.");
  }];
}

// ---------- Wi-Fi pairing (EZ/AP, kết quả qua delegate) ----------
//
// ⚠️ `ssid`/`password` LUÔN là của ROUTER (Wi-Fi nhà), KHÔNG phải hotspot `SmartLife…` do thiết bị
// phát ra. Header nói thẳng: "ssid: Name of route. password: Password of route."
// Việc nối điện thoại vào hotspot thiết bị là thao tác RIÊNG của user (AP mode), không liên quan
// tới 2 tham số này. Nhầm chỗ này = pair fail 100% mà lỗi trả về không hé lộ gì.
- (void)doWifiPairingMode:(NSString *)mode
                     ssid:(NSString *)ssid
                 password:(NSString *)password
                    token:(NSString *)token
               timeoutSec:(double)timeoutSec
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  self.wifiResolve = resolve;
  self.wifiReject = reject;
  BOOL isAp = [mode.uppercaseString isEqualToString:@"AP"];
  ThingActivatorMode m = isAp ? ThingActivatorModeAP : ThingActivatorModeEZ;
  [ThingSmartActivator sharedInstance].delegate = self;

  // EZ: doc EZ chỉ dùng biến thể KHÔNG có regInfo → giữ nguyên, đừng thêm thứ doc không yêu cầu.
  if (!isAp) {
    [[ThingSmartActivator sharedInstance] startConfigWiFi:m
                                                     ssid:ssid
                                                 password:password
                                                    token:token
                                                  timeout:timeoutSec];
    return;
  }

  // AP (legacy): doc quy định 3 bước — token → getDeviceSecurityConfigs → startConfigWiFi(regInfo).
  // Trước đây mình BỎ QUA bước security config và gọi thẳng biến thể không regInfo.
  // Signature verify verbatim từ header SDK thật (Pods/ThingSmartActivatorCoreKit/.../ThingSmartActivator.h:130-138):
  //   - (void)getDeviceSecurityConfigs:(ThingSuccessDict)success failure:(ThingFailureError)failure;
  //   - (void)startConfigWiFi:(ThingActivatorMode)mode ssid: password: token: regInfo:(nullable NSDictionary *) timeout:;
  __weak typeof(self) weakSelf = self;
  [[ThingSmartActivator sharedInstance] getDeviceSecurityConfigs:^(NSDictionary *result) {
    [weakSelf startApWithMode:m ssid:ssid password:password token:token regInfo:result timeout:timeoutSec];
  } failure:^(NSError *error) {
    // `regInfo` là nullable ⇒ KHÔNG chặn pairing khi lookup hỏng: thiết bị không cần security config
    // vẫn pair được bình thường. Chỉ emit để diagnostics phân biệt "không có config" vs "lỗi khác".
    //
    // ⚠️ Tên step CỐ Ý không chứa "fail"/"error", và CỐ Ý không set errorCode/errorMessage:
    //   · `isFailureStep()` (JS) khớp lỏng theo chuỗi fail/error ⇒ tên có "fail" sẽ bị xếp nhầm
    //     thành LỖI, trong khi đây là ca lành tính vẫn chạy tiếp.
    //   · set error* sẽ kích `setStepError` ⇒ UI hiện lỗi đỏ cho một thứ không phải lỗi, và nếu
    //     sau đó pair fail vì lý do KHÁC thì nó lại đổ tội nhầm chỗ này.
    // Chi tiết nhét vào dataJson (đã được đưa vào log chẩn đoán) - đủ để truy vết.
    [weakSelf emit:@"onPairingProgress" body:@{
      @"step": @"sdk.security_configs_skipped",
      @"dataJson": [NSString stringWithFormat:@"regInfo=nil; code=%@; message=%@",
                    error ? [@(error.code) stringValue] : @"?",
                    error.localizedDescription ?: @"(SDK không trả chi tiết)"],
    }];
    [weakSelf startApWithMode:m ssid:ssid password:password token:token regInfo:nil timeout:timeoutSec];
  }];
}

// Tách riêng để 2 nhánh (có/không lấy được security config) dùng chung đúng một đường gọi.
- (void)startApWithMode:(ThingActivatorMode)mode
                   ssid:(NSString *)ssid
               password:(NSString *)password
                  token:(NSString *)token
                regInfo:(nullable NSDictionary *)regInfo
                timeout:(double)timeoutSec {
  [[ThingSmartActivator sharedInstance] startConfigWiFi:mode
                                                   ssid:ssid
                                               password:password
                                                  token:token
                                                regInfo:regInfo
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
  } failure:^(NSError *e) {
    TuyaRejectNSError(reject, e, @"token_error", @"Không lấy được pairing token.");
  }];
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
    // NSError.code = mã Tuya thật (vd -55 token hết hạn, -1006 offline). ĐỪNG thay bằng literal.
    if (self.wifiReject) TuyaRejectNSError(self.wifiReject, error, @"pairing_error", @"Ghép nối Wi-Fi thất bại.");
  } else if (deviceModel) {
    if (self.wifiResolve) self.wifiResolve(TuyaPairResult(deviceModel));
  }
  self.wifiResolve = nil;
  self.wifiReject = nil;
  [activator stopConfigWiFi];
}

// Tiến trình trung gian (@optional của ThingSmartActivatorDelegate) → onPairingProgress.
//
// ⚠️ Callback này CÓ tham số `error` và SDK BÁO LỖI QUA ĐÂY - header ghi rõ:
//   "If this callback is received, the step is ThingActivatorStepFound, and
//    ThingSmartPairingConnectWiFiFailedErrorDomain is returned."
// Bản cũ chỉ emit `step` (dưới dạng SỐ) và VỨT `error` → lỗi "thiết bị không join được Wi-Fi"
// bị nuốt hoàn toàn. Giờ đẩy đủ code/message/domain lên JS.
- (void)activator:(ThingSmartActivator *)activator
   didReceiveDevice:(ThingSmartDeviceModel *)deviceModel
               step:(ThingActivatorStep)step
              error:(NSError *)error {
  NSMutableDictionary *body = [@{ @"step": TuyaActivatorStepName(step), @"dataJson": @"" } mutableCopy];
  if (deviceModel.devId.length) body[@"devId"] = deviceModel.devId;
  if (error) {
    body[@"errorCode"] = [@(error.code) stringValue];
    body[@"errorMessage"] = error.localizedDescription ?: @"";
    body[@"errorDomain"] = error.domain ?: @"";
  }
  [self emit:@"onPairingProgress" body:body];
}

// @optional - "Security Level Device" (cảm biến/khoá/*Security): SDK TẠM DỪNG giữa chừng, chờ app xác nhận
// (điều kiện: điện thoại cùng Wi-Fi vừa nhập) rồi mới đi tiếp. KHÔNG gọi continue → pairing TREO tới timeout.
// Sample chính chủ popup hỏi; ở đây AUTO-continue (preflight/prepare đã đảm bảo cùng Wi-Fi) + emit để log thấy.
// Xem docs/research/tuya-ios-sample-pairing-comparison.md §2.
- (void)activator:(ThingSmartActivator *)activator didPassWIFIToSecurityLevelDeviceWithUUID:(NSString *)uuid {
  [self emit:@"onPairingProgress" body:@{
    @"step": @"sdk.security_level_continue",
    @"dataJson": @"",
    @"devId": uuid ?: @"",
  }];
  [[ThingSmartActivator sharedInstance] continueConfigSecurityLevelDevice];
}

// @optional - kênh lỗi RIÊNG của SDK, trước đây không implement → mất trắng.
- (void)deviceStateError:(NSError *)error {
  if (!error) return;
  [self emit:@"onPairingProgress" body:@{
    @"step": @"device_state_error",
    @"dataJson": @"",
    @"errorCode": [@(error.code) stringValue],
    @"errorMessage": error.localizedDescription ?: @"",
    @"errorDomain": error.domain ?: @"",
  }];
}

// ---------- BLE scan ----------
- (void)startBleScan:(double)timeoutSec {
  [ThingSmartBLEManager sharedInstance].delegate = self;
  // Dùng startListening:YES (khớp sample chính chủ) thay startListeningWithType:Noraml.
  // ⚠️ ThingBLEScanType là BITMASK: Noraml(1)/QRCode(2)/AllDevice(4). `Noraml` quá HẸP → bỏ sót thiết bị
  // combo (Wi-Fi+BLE) mà Smart Life vẫn dò được. startListening: quét mặc định rộng như Smart Life.
  // (m1-fix-wifi-pairing: sensor combo không hiện ở auto-scan → đây là root cause.)
  [[ThingSmartBLEManager sharedInstance] startListening:YES];
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
    // bleType thật (trước hardcode 0) + isCombo → JS route: combo thì mới hỏi Wi-Fi (B8/B9).
    @"bleType": @((NSInteger)deviceInfo.bleType),
    @"isCombo": @(TuyaBleTypeIsCombo(deviceInfo.bleType)),
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
  if (!adv) {
    TuyaRejectWithDomain(reject, @"ble_scan_required", @"Chưa scan thấy uuid - gọi startBleScan() trước.", @"sdk");
    return;
  }
  [[ThingSmartBLEManager sharedInstance] activeBLE:adv
                                            homeId:(long long)homeId
                                           success:^(ThingSmartDeviceModel *m) { resolve(TuyaPairResult(m)); }
                                           failure:^{
    // ThingFailureHandler không có NSError → không thể lấy mã Tuya. Nói thẳng thay vì bịa mã.
    TuyaRejectWithDomain(reject, @"ble_pairing_error", @"Ghép nối BLE thất bại (SDK không trả chi tiết lỗi).", @"sdk");
  }];
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
  if (!adv) {
    TuyaRejectWithDomain(reject, @"ble_scan_required", @"Chưa scan thấy uuid - gọi startBleScan() trước.", @"sdk");
    return;
  }
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
    // ThingFailureHandler rỗng → không có mã Tuya. Kết quả thật (kèm NSError) về qua delegate bên dưới.
    if (self.comboReject) {
      TuyaRejectWithDomain(self.comboReject, @"combo_pairing_error",
                           @"Ghép nối BLE+Wi-Fi thất bại (SDK không trả chi tiết lỗi).", @"sdk");
    }
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
    if (self.comboReject) TuyaRejectNSError(self.comboReject, error, @"combo_pairing_error", @"Ghép nối BLE+Wi-Fi thất bại.");
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
