#import "TuyaPairing.h"
#import "TuyaReject.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>
// ⚠️ Nếu symbol BLE thiếu khi build: thêm #import <ThingSmartBLEKit/ThingSmartBLEKit.h> (manager/blewifi activator).

// TuyaPairing (iOS) - WIRED: token + Wi-Fi EZ/AP (ThingSmartActivator delegate) + BLE scan/pair (ThingSmartBLEManager)
// + combo BLE+Wi-Fi (ThingSmartBLEWifiActivator) + auto-token. Verbatim: docs/research/tuya-home-sdk-device-pairing.md
// + tuya-home-sdk-bluetooth.md. P3 nâng cao (sub-device / gateway / QR / wired / destroyActivator): ThingSmartActivator
// instance RIÊNG (alloc/init) + delegate riêng - selector verify với header Pods ThingSmartActivatorCoreKit/ThingSmartActivator.h.
// Đã verify header: ThingActivatorModeEZ/AP ✓; scan type = ThingBLEScanTypeNoraml (typo nguyên văn của SDK);
// combo dùng property bleWifiDelegate + callback bleWifiActivator:didReceiveBLEWifiConfigDevice:error: ✓;
// failure của activeBLE/startConfigBLEWifi là ThingFailureHandler (block rỗng - SDK không trả NSError).
//
// LỖI: mọi reject đi qua TuyaReject.h → shape { code, message, domain } khớp src/errors.ts.
// Trước đây reject bằng literal (@"pairing_error") làm MẤT NSError.code (mã Tuya thật) và nuốt message
// → app chỉ hiện "[sdk:pairing_error] Unknown error." Xem dev-workflow/m1-fix-wifi-pairing/.

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

// ---------- Pairing nâng cao: hằng + helper ----------
// Mặc định của SDK ("Timeout, default 100 seconds") khi JS truyền timeoutSec <= 0.
static const double kTuyaAdvDefaultTimeoutSec = 100;
// Lưới an toàn sau timeout của SDK (SDK tự báo timeout qua didReceiveDevice:error:, step 4).
static const double kTuyaAdvGraceSec = 15;

static NSString *TuyaJsonString(NSDictionary *obj) {
  if (![NSJSONSerialization isValidJSONObject:obj]) return @"{}";
  NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"{}";
}

// parseQRCode: trả NSDictionary {actionName, actionData}; uuid nằm trong actionData (dict, phòng khi là chuỗi JSON).
static NSString *TuyaQrUuid(id result, NSString **actionName) {
  NSDictionary *dict = [result isKindOfClass:[NSDictionary class]] ? result : nil;
  id name = dict[@"actionName"];
  if (actionName) *actionName = [name isKindOfClass:[NSString class]] ? name : @"";
  id data = dict[@"actionData"];
  if ([data isKindOfClass:[NSString class]]) {
    NSData *raw = [(NSString *)data dataUsingEncoding:NSUTF8StringEncoding];
    data = raw ? [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil] : nil;
  }
  id uuid = [data isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)data)[@"uuid"] : nil;
  return ([uuid isKindOfClass:[NSString class]] && [(NSString *)uuid length] > 0) ? uuid : nil;
}

// Delegate RIÊNG cho activator nâng cao (gateway / QR / wired / sub-device), tách khỏi delegate Wi-Fi (module +
// sharedInstance) để 2 luồng không giẫm nhau. ThingSmartActivator.delegate là weak ⇒ module giữ strong helper này.
// Callback LUÔN hop async sang main: module thả activator lúc settle mà không dealloc nó giữa callback của chính nó.
@interface TuyaAdvActivatorDelegate : NSObject <ThingSmartActivatorDelegate>
@property (nonatomic, assign) long long homeId; // > 0 ⇒ trả qua activatorGetHomeId: (QR / wired)
@property (nonatomic, copy) void (^onResult)(ThingSmartDeviceModel *model, NSError *error);
@property (nonatomic, copy) void (^onStep)(ThingSmartDeviceModel *model, ThingActivatorStep step, NSError *error);
@property (nonatomic, copy) void (^onGateway)(NSString *gwId, NSString *productId);
@property (nonatomic, copy) void (^onStateError)(NSError *error);
@end

@implementation TuyaAdvActivatorDelegate

// SDK hỏi respondsToSelector: trước khi gọi activatorGetHomeId: → homeId <= 0 thì "không trả lời" để SDK tự lấy
// (vd nhà gắn với token). Vì vậy phải set homeId TRƯỚC khi gán làm delegate.
- (BOOL)respondsToSelector:(SEL)selector {
  if (selector == @selector(activatorGetHomeId:)) return self.homeId > 0;
  return [super respondsToSelector:selector];
}

- (long long)activatorGetHomeId:(ThingSmartActivator *)activator { return self.homeId; }

// Kết quả cuối (SDK gọi cho step 0/3/4: thành công, hoặc lỗi kể cả timeout) - sub-device: gọi cho TỪNG thiết bị.
- (void)activator:(ThingSmartActivator *)activator
   didReceiveDevice:(ThingSmartDeviceModel *)deviceModel
              error:(NSError *)error {
  void (^cb)(ThingSmartDeviceModel *, NSError *) = self.onResult;
  if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(deviceModel, error); });
}

- (void)activator:(ThingSmartActivator *)activator
   didReceiveDevice:(ThingSmartDeviceModel *)deviceModel
               step:(ThingActivatorStep)step
              error:(NSError *)error {
  void (^cb)(ThingSmartDeviceModel *, ThingActivatorStep, NSError *) = self.onStep;
  if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(deviceModel, step, error); });
}

// Thiết bị nối dây/gateway chưa kích hoạt broadcast trên LAN (cùng mạng với điện thoại).
- (void)activator:(ThingSmartActivator *)activator
    didFindGatewayWithDeviceId:(NSString *)deviceId
                     productId:(NSString *)productId {
  void (^cb)(NSString *, NSString *) = self.onGateway;
  if (cb) dispatch_async(dispatch_get_main_queue(), ^{ cb(deviceId, productId); });
}

- (void)deviceStateError:(NSError *)error {
  void (^cb)(NSError *) = self.onStateError;
  if (cb && error) dispatch_async(dispatch_get_main_queue(), ^{ cb(error); });
}

@end

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
// Pairing nâng cao gateway / QR / wired: 1 phiên tại 1 thời điểm; state CHỈ đụng trên main queue.
@property (nonatomic, strong) ThingSmartActivator *advActivator;
@property (nonatomic, strong) TuyaAdvActivatorDelegate *advDelegate;
@property (nonatomic, copy) RCTPromiseResolveBlock advResolve;
@property (nonatomic, copy) RCTPromiseRejectBlock advReject;
@property (nonatomic, assign) NSUInteger advGeneration;
// Sub-device: slot riêng (void, kết quả qua event) để không đá phiên gateway/QR/wired.
@property (nonatomic, strong) ThingSmartActivator *subActivator;
@property (nonatomic, strong) TuyaAdvActivatorDelegate *subDelegate;
@property (nonatomic, copy) NSString *subGwId;
@property (nonatomic, assign) NSUInteger subGeneration;
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
  // Dùng thẳng tên class thay `typeof(self)`: `typeof` là GNU extension, ở chế độ biên dịch ObjC++ này
  // clang không nhận (báo "Expected unqualified-id") ⇒ khai báo weakSelf hỏng. `__weak TuyaPairing *` luôn OK.
  __weak TuyaPairing *weakSelf = self;
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

// ---------- P3: pairing nâng cao (ThingSmartActivator instance riêng + TuyaAdvActivatorDelegate) ----------
// Step trung gian → onPairingProgress cùng tên/shape với Wi-Fi (TuyaActivatorStepName); kết quả cuối → promise.

// Sub-device (Zigbee/BLE qua gateway): gateway phải online cloud, KHÔNG cần token. Mỗi sub-device ghép xong →
// onPairingProgress(step='subdevice_found', dataJson=devId, devId); lỗi/timeout → step='subdevice_error' + error*.
- (void)startSubDevicePairing:(NSString *)gatewayDevId timeoutSec:(double)timeoutSec {
  double t = timeoutSec > 0 ? timeoutSec : kTuyaAdvDefaultTimeoutSec;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self stopSubDeviceActivator];
    NSUInteger gen = self.subGeneration;
    __weak TuyaPairing *weakSelf = self;
    TuyaAdvActivatorDelegate *d = [TuyaAdvActivatorDelegate new];
    d.onResult = ^(ThingSmartDeviceModel *model, NSError *error) {
      TuyaPairing *s = weakSelf;
      if (!s || s.subGeneration != gen) return;
      if (error) {
        [s emit:@"onPairingProgress" body:@{
          @"step": @"subdevice_error",
          @"dataJson": @"",
          @"errorCode": [@(error.code) stringValue],
          @"errorMessage": error.localizedDescription ?: @"",
          @"errorDomain": error.domain ?: @"",
        }];
      } else if (model.devId.length) {
        [s emit:@"onPairingProgress" body:@{ @"step": @"subdevice_found", @"dataJson": model.devId, @"devId": model.devId }];
      }
    };
    d.onStep = ^(ThingSmartDeviceModel *model, ThingActivatorStep step, NSError *error) {
      TuyaPairing *s = weakSelf;
      if (s && s.subGeneration == gen) [s emitAdvStep:step model:model error:error];
    };
    d.onStateError = ^(NSError *error) {
      TuyaPairing *s = weakSelf;
      if (s && s.subGeneration == gen) [s emitStateError:error];
    };
    ThingSmartActivator *act = [[ThingSmartActivator alloc] init];
    act.delegate = d;
    self.subActivator = act;
    self.subDelegate = d;
    self.subGwId = gatewayDevId;
    [act activeSubDeviceWithGwId:gatewayDevId timeout:t];
  });
}

- (void)stopSubDevicePairing:(NSString *)gatewayDevId {
  dispatch_async(dispatch_get_main_queue(), ^{ [self stopSubDeviceActivator]; });
}

// Gateway (nối dây / đã ở trong LAN) biết trước gwId + productId: SDK chờ broadcast của đúng gwId rồi gửi token.
// Điện thoại phải cùng mạng với gateway; gwId/productId lấy từ event 'gateway_found' (startWiredPairing) hoặc tem thiết bị.
- (void)startGatewayPairing:(NSString *)gatewayDevId
                  productId:(NSString *)productId
                      token:(NSString *)token
                 timeoutSec:(double)timeoutSec
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject {
  if (gatewayDevId.length == 0 || token.length == 0) {
    TuyaRejectWithDomain(reject, @"invalid_argument", @"gatewayDevId and token are required.", @"sdk");
    return;
  }
  double t = timeoutSec > 0 ? timeoutSec : kTuyaAdvDefaultTimeoutSec;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self beginAdvFlow:@"gateway" homeId:0 timeout:t resolve:resolve reject:reject];
    [self.advActivator activeGatewayDeviceWithGwId:gatewayDevId
                                         productId:(productId ?: @"")
                                             token:token
                                           timeout:t];
  });
}

// QR in trên thiết bị (thiết bị đã online internet, vd 4G): doc "Device QR Code Pairing" - parseQRCode → uuid →
// ThingSmartPairConfiguration(uuid, gid=homeId) → startActiveDeviceWithConfigurations: mode MQTTDirectly. Token SDK
// tự lấy theo uuid (getQRToken nội bộ - đã xem SDK) ⇒ không cần getTokenWithUUID. assetId: chỉ API hợp nhất mới dùng → bỏ qua.
- (void)startQrPairing:(double)homeId
               assetId:(NSString *)assetId
                  code:(NSString *)code
            timeoutSec:(double)timeoutSec
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  if (code.length == 0) {
    TuyaRejectWithDomain(reject, @"invalid_argument", @"QR code content is empty.", @"sdk");
    return;
  }
  double t = timeoutSec > 0 ? timeoutSec : kTuyaAdvDefaultTimeoutSec;
  dispatch_async(dispatch_get_main_queue(), ^{
    NSUInteger gen = [self beginAdvFlow:@"qr" homeId:(long long)homeId timeout:t resolve:resolve reject:reject];
    __weak TuyaPairing *weakSelf = self;
    [ThingSmartActivator parseQRCode:code success:^(id result) {
      dispatch_async(dispatch_get_main_queue(), ^{
        TuyaPairing *s = weakSelf;
        if (!s || s.advGeneration != gen || !s.advReject) return;
        NSString *actionName = @"";
        NSString *uuid = TuyaQrUuid(result, &actionName);
        if (uuid.length == 0) {
          NSString *desc = [result description] ?: @"(nil)";
          if (desc.length > 300) desc = [[desc substringToIndex:300] stringByAppendingString:@"..."];
          [s finishAdv:^(RCTPromiseResolveBlock res, RCTPromiseRejectBlock rej) {
            TuyaRejectWithDomain(rej, @"qr_uuid_missing",
                [NSString stringWithFormat:@"QR parsed (actionName=%@) but actionData has no uuid: %@", actionName, desc],
                @"sdk");
          }];
          return;
        }
        [s emit:@"onPairingProgress" body:@{
          @"step": @"qr_parsed",
          @"dataJson": TuyaJsonString(@{ @"actionName": actionName ?: @"", @"uuid": uuid }),
        }];
        ThingSmartPairConfiguration *config = [[ThingSmartPairConfiguration alloc] init];
        config.uuid = uuid;
        config.gid = [NSString stringWithFormat:@"%lld", (long long)homeId];
        [s.advActivator startActiveDeviceWithConfigurations:config mode:ThingActivatorModeMQTTDirectly timeout:t];
      });
    } failure:^(NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        TuyaPairing *s = weakSelf;
        if (!s || s.advGeneration != gen || !s.advReject) return;
        [s finishAdv:^(RCTPromiseResolveBlock res, RCTPromiseRejectBlock rej) {
          TuyaRejectNSError(rej, error, @"qr_parse_error", @"parseQRCode failed.");
        }];
      });
    }];
  });
}

// Wired (thiết bị nối dây, chưa biết gwId): doc "Wired Mode" = startConfigWiFiWithToken:timeout: - đã disassemble:
// đúng bằng activeGatewayDeviceWithGwId:nil productId:nil token:timeout: ⇒ SDK nghe broadcast trên LAN và activate
// thiết bị nó thấy. Deprecated chỉ vì bản mới muốn biết trước gwId (ở đây không có). Thiết bị thấy → 'gateway_found'.
- (void)startWiredPairing:(double)homeId
                    token:(NSString *)token
               timeoutSec:(double)timeoutSec
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  if (token.length == 0) {
    TuyaRejectWithDomain(reject, @"invalid_argument", @"token is required (getPairingToken(homeId)).", @"sdk");
    return;
  }
  double t = timeoutSec > 0 ? timeoutSec : kTuyaAdvDefaultTimeoutSec;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self beginAdvFlow:@"wired" homeId:(long long)homeId timeout:t resolve:resolve reject:reject];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self.advActivator startConfigWiFiWithToken:token timeout:t];
#pragma clang diagnostic pop
  });
}

- (void)destroyActivator {
  [[ThingSmartActivator sharedInstance] stopConfigWiFi];
  [ThingSmartActivator sharedInstance].delegate = nil;
  self.comboActivator.bleWifiDelegate = nil;
  self.comboActivator = nil;
  [self.scanned removeAllObjects];
  // Pairing nâng cao: phiên gateway/QR/wired đang chờ → reject 'pairing_cancelled'; dừng sub-device.
  dispatch_async(dispatch_get_main_queue(), ^{
    [self cancelAdvFlow:@"destroyActivator() was called."];
    [self stopSubDeviceActivator];
  });
}

// ---------- helper pairing nâng cao (GỌI TRÊN MAIN QUEUE) ----------

// Mở phiên gateway/QR/wired: phiên cũ còn chờ → reject 'pairing_cancelled'; tạo activator + delegate mới.
// Trả generation để callback async (parseQRCode) nhận ra phiên đã bị thay.
- (NSUInteger)beginAdvFlow:(NSString *)what
                    homeId:(long long)homeId
                   timeout:(double)timeoutSec
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject {
  [self cancelAdvFlow:[NSString stringWithFormat:@"Superseded by a new %@ pairing request.", what]];
  NSUInteger gen = ++self.advGeneration;
  self.advResolve = resolve;
  self.advReject = reject;

  __weak TuyaPairing *weakSelf = self;
  TuyaAdvActivatorDelegate *d = [TuyaAdvActivatorDelegate new];
  d.homeId = homeId; // set TRƯỚC khi gán delegate (xem respondsToSelector:)
  d.onResult = ^(ThingSmartDeviceModel *model, NSError *error) {
    TuyaPairing *s = weakSelf;
    if (!s || s.advGeneration != gen) return;
    if (error) {
      // NSError.code = mã Tuya thật (vd token hết hạn / timeout). ĐỪNG thay bằng literal.
      [s finishAdv:^(RCTPromiseResolveBlock res, RCTPromiseRejectBlock rej) {
        TuyaRejectNSError(rej, error, [what stringByAppendingString:@"_pairing_error"],
                          [NSString stringWithFormat:@"Pairing (%@) failed.", what]);
      }];
    } else if (model) {
      [s finishAdv:^(RCTPromiseResolveBlock res, RCTPromiseRejectBlock rej) { res(TuyaPairResult(model)); }];
    }
  };
  d.onStep = ^(ThingSmartDeviceModel *model, ThingActivatorStep step, NSError *error) {
    TuyaPairing *s = weakSelf;
    if (s && s.advGeneration == gen) [s emitAdvStep:step model:model error:error];
  };
  d.onGateway = ^(NSString *gwId, NSString *productId) {
    TuyaPairing *s = weakSelf;
    if (s && s.advGeneration == gen) [s emitGatewayFound:gwId productId:productId];
  };
  d.onStateError = ^(NSError *error) {
    TuyaPairing *s = weakSelf;
    if (s && s.advGeneration == gen) [s emitStateError:error];
  };
  ThingSmartActivator *act = [[ThingSmartActivator alloc] init];
  act.delegate = d;
  self.advActivator = act;
  self.advDelegate = d;

  // Lưới an toàn: chỉ khi SDK im lặng quá timeout + grace (bình thường SDK tự báo timeout qua onResult).
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeoutSec + kTuyaAdvGraceSec) * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    TuyaPairing *s = weakSelf;
    if (!s || s.advGeneration != gen || !s.advReject) return;
    [s finishAdv:^(RCTPromiseResolveBlock res, RCTPromiseRejectBlock rej) {
      TuyaRejectWithDomain(rej, @"pairing_timeout",
          [NSString stringWithFormat:@"No %@ pairing result from the SDK within %.0fs.", what, timeoutSec + kTuyaAdvGraceSec],
          @"sdk");
    }];
  });
  return gen;
}

// Kết thúc phiên đúng 1 lần: lấy promise ra, dừng + thả activator, rồi resolve/reject.
- (void)finishAdv:(void (^)(RCTPromiseResolveBlock resolve, RCTPromiseRejectBlock reject))finish {
  RCTPromiseResolveBlock res = self.advResolve;
  RCTPromiseRejectBlock rej = self.advReject;
  self.advResolve = nil;
  self.advReject = nil;
  ThingSmartActivator *act = self.advActivator;
  self.advActivator = nil;
  self.advDelegate = nil;
  if (act) {
    act.delegate = nil;
    [act stopConfigWiFi];
    // Giữ instance thêm 1 vòng main queue: không dealloc activator ngay trong call stack của chính nó.
    dispatch_async(dispatch_get_main_queue(), ^{ (void)act; });
  }
  if (res && rej) finish(res, rej);
}

- (void)cancelAdvFlow:(NSString *)reason {
  if (!self.advActivator && !self.advReject) return;
  [self finishAdv:^(RCTPromiseResolveBlock res, RCTPromiseRejectBlock rej) {
    TuyaRejectWithDomain(rej, @"pairing_cancelled", reason, @"sdk");
  }];
}

- (void)stopSubDeviceActivator {
  ThingSmartActivator *act = self.subActivator;
  NSString *gwId = self.subGwId;
  self.subGeneration++;
  self.subActivator = nil;
  self.subDelegate = nil;
  self.subGwId = nil;
  if (!act) return;
  act.delegate = nil;
  if (gwId.length) [act stopActiveSubDeviceWithGwId:gwId];
  dispatch_async(dispatch_get_main_queue(), ^{ (void)act; });
}

// Step của activator nâng cao → onPairingProgress, cùng shape/tên với luồng Wi-Fi.
- (void)emitAdvStep:(ThingActivatorStep)step model:(ThingSmartDeviceModel *)model error:(NSError *)error {
  NSMutableDictionary *body = [@{ @"step": TuyaActivatorStepName(step), @"dataJson": @"" } mutableCopy];
  if (model.devId.length) body[@"devId"] = model.devId;
  if (error) {
    body[@"errorCode"] = [@(error.code) stringValue];
    body[@"errorMessage"] = error.localizedDescription ?: @"";
    body[@"errorDomain"] = error.domain ?: @"";
  }
  [self emit:@"onPairingProgress" body:body];
}

- (void)emitGatewayFound:(NSString *)gwId productId:(NSString *)productId {
  [self emit:@"onPairingProgress" body:@{
    @"step": @"gateway_found",
    @"dataJson": TuyaJsonString(@{ @"gwId": gwId ?: @"", @"productId": productId ?: @"" }),
    @"devId": gwId ?: @"",
  }];
}

- (void)emitStateError:(NSError *)error {
  [self emit:@"onPairingProgress" body:@{
    @"step": @"device_state_error",
    @"dataJson": @"",
    @"errorCode": [@(error.code) stringValue],
    @"errorMessage": error.localizedDescription ?: @"",
    @"errorDomain": error.domain ?: @"",
  }];
}

- (void)dealloc {
  [ThingSmartActivator sharedInstance].delegate = nil;
  _comboActivator.bleWifiDelegate = nil;
  _advActivator.delegate = nil;
  [_advActivator stopConfigWiFi];
  _subActivator.delegate = nil;
  if (_subGwId.length) [_subActivator stopActiveSubDeviceWithGwId:_subGwId];
}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) - không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaPairingSpecJSI>(params);
}

@end
