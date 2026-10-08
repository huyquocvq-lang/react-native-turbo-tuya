#import "TuyaMatter.h"
#import "TuyaReject.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>
#import <ThingSmartActivatorDiscoveryManager/ThingSmartActivatorDiscoveryManager.h>
#import <ThingSmartMatterInterfaceAPI/ThingSmartMatterInterfaceAPI.h>
#import <ThingModuleManager/ThingModule.h>

// TuyaMatter (iOS) - WIRED trên API HỢP NHẤT ThingSmartActivatorDiscovery (+Matter), verify bằng header Pods
// (ThingSmartActivatorDiscoveryManager 1.14.6 / ThingSmartMatterInterfaceAPI 1.7.1) + sample chính chủ
// tuya-home-ios-sdk-sample-swift (BEMatterTableViewController):
//   type model: [ThingSmartActivatorTypeMatterModel new] + type = ThingSmartActivatorTypeMatter
//               + typeName = NSStringFromThingSmartActivatorType(ThingSmartActivatorTypeMatter) + timeout (giây)
//   discovery : registerWithActivatorList:@[type] → setupDelegate: → loadConfig
//   parse     : parseSetupCode: → ThingSmartActivatorDeviceModel (GIỮ; payload nằm ở property nội bộ `matterPayload`)
//   connect   : token (getTokenWithHomeId) → type.token/spaceId → startActive:deviceList:@[model]
//               → delegate matterCommissioningSessionEstablishmentComplete: (PASE xong) = "connected"
//   commission: type.ssid/password (Wi-Fi) | gwDevId (Thread) → continueCommissionDevice:typeModel:
//               → activatorService:activatorType:didReceiveDevices:error:
//   attestation: matterDeviceAttestation:error: → continueCommissioningDevice:ignoreAttestationFailure:error:
//   cancel    : stopActive:clearCache: (bên trong gọi cancelActivator của Matter service)
// KHÁC Android: SDK nhét token vào ThingConnectDeviceBuilder ngay lúc startActive → token lấy trong connectDevice;
//   tham số `token` của commissionDevice bị bỏ qua. `timeoutSec` của connectDevice là timeout cả phiên của SDK.
// Prereq app (không thuộc lib) - theo docs Tuya "Prepare for Integration with Matter Device": pod ThingSmartMatterKit
//   (app) + target Matter Extension (Swift, iOS 16.1+) với pod ThingSmartMatterExtensionKit (thiếu implementation thì
//   ThingModule không có service ThingActivatorMatterInterfaceProtocol → reject matter_unavailable);
//   [ThingSmartMatterActivatorConfig setMatterConfigKey:@"<App Group>"] ngay sau khi SDK start; capability Matter
//   Allow Setup Payload + App Groups + Background Modes (BLE accessories); NSBonjourServices _meshcop._udp,
//   _matter._tcp, _matterc._udp, _matterd._udp + quyền BLE/LAN.

// Đọc property nội bộ (không có trong header public) an toàn: thiếu selector → nil, không crash.
static id TuyaMatterKVC(id obj, NSString *key) {
  if (!obj || ![obj respondsToSelector:NSSelectorFromString(key)]) { return nil; }
  @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}

static ThingMatterSetupPayload *TuyaMatterPayloadOf(ThingSmartActivatorDeviceModel *d) {
  id p = TuyaMatterKVC(d, @"matterPayload");
  return [p isKindOfClass:[ThingMatterSetupPayload class]] ? p : nil;
}

static ThingMatterDeviceModel *TuyaMatterDeviceOf(ThingSmartActivatorDeviceModel *d) {
  id m = TuyaMatterKVC(d, @"matterDeviceModel");
  return [m isKindOfClass:[ThingMatterDeviceModel class]] ? m : nil;
}

// Matter implementation (ThingSmartMatterKit) có được link vào app không - cùng cách discovery manager tra service.
static BOOL TuyaMatterAvailable(void) {
  return [ThingModule serviceOfOptionalProtocol:@protocol(ThingActivatorMatterInterfaceProtocol)] != nil;
}

static NSString *const kTuyaMatterUnavailableMsg =
    @"Tuya Matter implementation is not linked: no ThingActivatorMatterInterfaceProtocol service "
    @"(add pod ThingSmartMatterKit + ThingSmartMatterExtensionKit to the app).";

// Tên kiểu thiết bị thống nhất với Android: unknown | wifi | thread | softAP | onNetwork.
static NSString *TuyaMatterTypeName(ThingMatterDeviceType t) {
  switch (t) {
    case ThingMatterDeviceTypeWifi:
    case ThingMatterDeviceTypeWifiSupport5G: return @"wifi";
    case ThingMatterDeviceTypeThread:
    case ThingMatterDeviceTypeThreadSupportBLE: return @"thread";
    case ThingMatterDeviceTypeAP: return @"softAP";
    case ThingMatterDeviceTypeOnNetwork: return @"onNetwork";
    default: return @"unknown";
  }
}

static NSString *TuyaMatterRouteTypeName(ThingActivatorMatterDeviceType t) {
  switch (t) {
    case ThingActivatorMatterDeviceTypeWifi: return @"wifi";
    case ThingActivatorMatterDeviceTypeThread: return @"thread";
    case ThingActivatorMatterDeviceTypeAP: return @"softAP";
    case ThingActivatorMatterDeviceTypeOnNetwork: return @"onNetwork";
    default: return @"unknown";
  }
}

static NSString *TuyaMatterJson(NSDictionary *obj) {
  if (![NSJSONSerialization isValidJSONObject:obj]) { return @"{}"; }
  NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"{}";
}

// Reject mang mã lỗi Tuya THẬT (NSError.code + message nguyên văn); không có NSError → fallback.
static void TuyaMatterReject(RCTPromiseRejectBlock reject, NSError *error, NSString *fallbackCode, NSString *fallbackMessage) {
  if (error) {
    TuyaRejectWithDomain(reject, [@(error.code) stringValue], error.localizedDescription, @"sdk");
  } else {
    TuyaRejectWithDomain(reject, fallbackCode, fallbackMessage, @"sdk");
  }
}

// State chỉ đụng trên main (methodQueue = main) → callback SDK lỡ về thread khác thì nhảy về main.
static void TuyaMatterOnMain(dispatch_block_t block) {
  if ([NSThread isMainThread]) { block(); } else { dispatch_async(dispatch_get_main_queue(), block); }
}

static NSDictionary *TuyaMatterPaired(ThingSmartActivatorDeviceModel *d) {
  ThingSmartDeviceModel *dm = nil;
  id x = TuyaMatterKVC(d, @"deviceModel");
  if ([x isKindOfClass:[ThingSmartDeviceModel class]]) { dm = x; }
  if (!dm) { dm = TuyaMatterDeviceOf(d).deviceModel; }
  NSString *devId = d.devId.length ? d.devId : (dm.devId.length ? dm.devId : (d.uniqueID ?: @""));
  return @{ @"devId": devId ?: @"",
            @"name": d.name.length ? d.name : (dm.name ?: @""),
            @"productId": d.productId.length ? d.productId : (dm.productId ?: @"") };
}

@interface TuyaMatter () <ThingSmartActivatorSearchDelegate, ThingSmartActivatorActiveDelegate, ThingSmartActivatorDeviceExpandDelegate>
@property (nonatomic, strong) ThingSmartActivatorDiscovery *discovery;
@property (nonatomic, strong) ThingSmartActivatorTypeMatterModel *typeModel;
@property (nonatomic, strong) ThingSmartActivatorDeviceModel *setupDevice;   // từ parseSetupCode
@property (nonatomic, strong) ThingSmartActivatorDeviceModel *sessionDevice; // PASE xong (connectDevice)
@property (nonatomic, strong) ThingMatterDeviceDiscoveriedType *routeInfo;   // matterDeviceDiscoveryed:
@property (nonatomic, strong) NSDictionary *pairedEarly;                     // pair xong trước khi commissionDevice
@property (nonatomic, strong) NSError *lateError;                            // lỗi SDK khi không có promise chờ
@property (nonatomic, assign) void *attestationDevice;                       // con trỏ native, chỉ dùng 1 lần
@property (nonatomic, assign) BOOL activeStarted;
@property (nonatomic, assign) NSUInteger connectGen;
@property (nonatomic, assign) NSUInteger commissionGen;
@property (nonatomic, copy) RCTPromiseResolveBlock connectResolve;
@property (nonatomic, copy) RCTPromiseRejectBlock connectReject;
@property (nonatomic, copy) RCTPromiseResolveBlock commissionResolve;
@property (nonatomic, copy) RCTPromiseRejectBlock commissionReject;
@end

@implementation TuyaMatter

RCT_EXPORT_MODULE()

// SDK gọi delegate trên main → chạy method trên main luôn để state không bị race.
- (dispatch_queue_t)methodQueue { return dispatch_get_main_queue(); }

- (NSArray<NSString *> *)supportedEvents {
  return @[@"onMatterDeviceFound", @"onMatterAttestation", @"onMatterError"];
}

- (ThingSmartActivatorTypeMatterModel *)typeModel {
  if (!_typeModel) {
    ThingSmartActivatorTypeMatterModel *t = [[ThingSmartActivatorTypeMatterModel alloc] init];
    t.type = ThingSmartActivatorTypeMatter;
    t.typeName = NSStringFromThingSmartActivatorType(ThingSmartActivatorTypeMatter);
    t.timeout = 180;
    _typeModel = t;
  }
  return _typeModel;
}

- (ThingSmartActivatorDiscovery *)discovery {
  if (!_discovery) {
    ThingSmartActivatorDiscovery *d = [[ThingSmartActivatorDiscovery alloc] init];
    [d registerWithActivatorList:@[self.typeModel]];
    [d setupDelegate:self];
    [d loadConfig];
    _discovery = d;
  }
  return _discovery;
}

- (void)emitError:(NSString *)code message:(NSString *)message {
  [self emit:@"onMatterError" body:@{ @"code": code ?: @"matter_error", @"message": message ?: @"" }];
}

// ---------- 1) Parse "MT:..." / manual code → payload (native giữ device model) ----------
- (void)parseSetupCode:(NSString *)code
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  if (!TuyaMatterAvailable()) {
    TuyaRejectWithDomain(reject, @"matter_unavailable", kTuyaMatterUnavailableMsg, @"sdk");
    return;
  }
  NSString *trimmed = [code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  ThingSmartActivatorDeviceModel *dev = [self.discovery parseSetupCode:trimmed];
  if (!dev) {
    TuyaRejectWithDomain(reject, @"matter_invalid_setup_code",
                         @"Invalid Matter setup code: expected a QR payload ('MT:...') or an 11/21-digit manual pairing code.",
                         @"sdk");
    return;
  }
  [self resetSession];
  self.setupDevice = dev;
  // Payload là property nội bộ → nếu SDK đổi tên thì trả 0 (luồng connect/commission vẫn chạy bằng device model).
  ThingMatterSetupPayload *p = TuyaMatterPayloadOf(dev);
  resolve(@{ @"version": p.version ?: @0,
             @"vendorId": p.vendorID ?: @0,
             @"productId": p.productID ?: @0,
             @"setupPinCode": p.setUpPINCode ?: @0,
             @"discriminator": p.discriminator ?: @0 });
}

// ---------- 2) Connect: token + startActive → resolve khi phiên PASE thiết lập xong ----------
- (void)connectDevice:(double)homeId
           timeoutSec:(double)timeoutSec
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject {
  ThingSmartActivatorDeviceModel *dev = self.setupDevice;
  if (!dev) {
    TuyaRejectWithDomain(reject, @"matter_setup_code_required", @"Call parseSetupCode first.", @"sdk");
    return;
  }
  [self settleConnect:nil error:nil code:@"matter_superseded"
              message:@"connectDevice was called again before the previous call finished."];
  if (self.activeStarted) { [self.discovery stopActive:@[self.typeModel] clearCache:YES]; self.activeStarted = NO; }
  self.sessionDevice = nil;
  self.routeInfo = nil;
  self.pairedEarly = nil;
  self.lateError = nil;
  self.connectResolve = resolve;
  self.connectReject = reject;
  NSUInteger gen = ++self.connectGen;
  NSTimeInterval timeout = timeoutSec > 0 ? timeoutSec : 180;

  [[ThingSmartActivator sharedInstance] getTokenWithHomeId:(long long)homeId success:^(NSString *token) {
    TuyaMatterOnMain(^{
      if (gen != self.connectGen || !self.connectReject) { return; }
      self.typeModel.token = token ?: @"";
      self.typeModel.spaceId = (long long)homeId;
      self.typeModel.timeout = timeout;
      self.typeModel.ssid = @"";
      self.typeModel.password = @"";
      self.typeModel.gwDevId = @"";
      self.activeStarted = YES;
      [self.discovery startActive:self.typeModel deviceList:@[dev]];
      // Chốt chặn: SDK tự timeout (báo qua didReceiveDevices) - đây chỉ phòng trường hợp SDK im lặng.
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 5) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gen != self.connectGen || !self.connectReject) { return; }
        [self.discovery stopActive:@[self.typeModel] clearCache:YES];
        self.activeStarted = NO;
        [self settleConnect:nil error:nil code:@"matter_connect_timeout"
                    message:[NSString stringWithFormat:@"No Matter session was established within %.0fs.", timeout]];
      });
    });
  } failure:^(NSError *e) {
    TuyaMatterOnMain(^{
      if (gen != self.connectGen) { return; }
      [self settleConnect:nil error:e code:@"token_error" message:@"Failed to get a pairing token."];
    });
  }];
}

// ---------- 3) Commission: Wi-Fi (ssid/password) hoặc Thread (gateway) → thiết bị hoàn tất ----------
- (void)commissionDevice:(double)homeId
                   token:(NSString *)token
                    ssid:(NSString *)ssid
                password:(NSString *)password
              timeoutSec:(double)timeoutSec
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  if (self.pairedEarly) { // SDK đã hoàn tất ngay trong bước connect (vd. thiết bị không cần cấu hình mạng)
    resolve(self.pairedEarly);
    [self resetSession];
    return;
  }
  if (self.lateError) {
    NSError *e = self.lateError;
    self.lateError = nil;
    TuyaMatterReject(reject, e, @"matter_commission_error", @"Matter commissioning failed.");
    return;
  }
  ThingSmartActivatorDeviceModel *session = self.sessionDevice;
  if (!session) {
    TuyaRejectWithDomain(reject, @"matter_connect_required",
                         @"Call connectDevice first (no established Matter session held).", @"sdk");
    return;
  }
  // Header: continueCommissionDevice: CHỈ dùng khi routingType == Thing; routing khác (MatterSupport/share)
  // SDK tự đi tiếp → chỉ chờ kết quả qua didReceiveDevices.
  BOOL thingRouting = !self.routeInfo || self.routeInfo.routingType == ThingActivatorMatterRoutingTypeThing;
  // SDK: ssid rỗng → rẽ nhánh Thread (gateway) → thiết bị Wi-Fi sẽ fail mơ hồ; chặn sớm với lỗi rõ ràng.
  if (thingRouting && ssid.length == 0 && [[self typeNameFor:session] isEqualToString:@"wifi"]) {
    TuyaRejectWithDomain(reject, @"matter_wifi_required",
                         @"This Matter device joins Wi-Fi: pass the router ssid/password to commissionDevice.", @"sdk");
    return;
  }
  [self settleCommission:nil error:nil code:@"matter_superseded"
                 message:@"commissionDevice was called again before the previous call finished."];
  self.commissionResolve = resolve;
  self.commissionReject = reject;
  NSUInteger gen = ++self.commissionGen;

  if (thingRouting) {
    // ssid rỗng hoặc không phải thiết bị Wi-Fi → SDK rẽ nhánh Thread (gắn gateway gwDevId).
    self.typeModel.ssid = ssid ?: @"";
    self.typeModel.password = password ?: @"";
    ThingMatterDeviceModel *md = TuyaMatterDeviceOf(session);
    NSString *gw = md.gatewayId.length ? md.gatewayId : [session deviceScanThreadGateway];
    self.typeModel.gwDevId = gw ?: @"";
    [self.discovery continueCommissionDevice:session typeModel:self.typeModel];
  }

  NSTimeInterval timeout = timeoutSec > 0 ? timeoutSec : 180;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (gen != self.commissionGen || !self.commissionReject) { return; }
    [self.discovery stopActive:@[self.typeModel] clearCache:YES];
    self.activeStarted = NO;
    [self settleCommission:nil error:nil code:@"matter_commission_timeout"
                   message:[NSString stringWithFormat:@"Matter commissioning did not finish within %.0fs.", timeout]];
  });
}

// ---------- Auto-discovery (kết quả qua onMatterDeviceFound) ----------
- (void)startDiscovery {
  if (!TuyaMatterAvailable()) { [self emitError:@"matter_unavailable" message:kTuyaMatterUnavailableMsg]; return; }
  [self.discovery startSearch:@[self.typeModel]];
}

- (void)stopDiscovery {
  if (_discovery) { [_discovery stopSearch:@[self.typeModel] clearCache:YES]; }
}

// ---------- Attestation / cancel ----------
- (void)continueCommissioning:(BOOL)ignoreAttestationFailure {
  void *device = self.attestationDevice;
  if (!device) {
    [self emitError:@"matter_no_attestation_pending"
            message:@"continueCommissioning called without a pending onMatterAttestation."];
    return;
  }
  self.attestationDevice = NULL;
  NSError *error = nil;
  [self.discovery continueCommissioningDevice:device ignoreAttestationFailure:ignoreAttestationFailure error:&error];
  if (error) { [self emitError:[@(error.code) stringValue] message:error.localizedDescription]; }
}

- (void)cancelActivator {
  if (_discovery) { [_discovery stopActive:@[self.typeModel] clearCache:YES]; }
  self.activeStarted = NO;
  [self settleConnect:nil error:nil code:@"matter_cancelled" message:@"Matter activation cancelled by cancelActivator()."];
  [self settleCommission:nil error:nil code:@"matter_cancelled" message:@"Matter activation cancelled by cancelActivator()."];
  [self resetSession];
}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) - không khai lại.

- (void)invalidate {
  if (_discovery) {
    [_discovery stopSearch:@[self.typeModel] clearCache:YES];
    if (self.activeStarted) { [_discovery stopActive:@[self.typeModel] clearCache:YES]; }
    [_discovery removeDelegate:self];
  }
  self.activeStarted = NO;
  self.connectResolve = nil; self.connectReject = nil;
  self.commissionResolve = nil; self.commissionReject = nil;
  [super invalidate];
}

// ---------- state helpers ----------
- (void)resetSession {
  self.sessionDevice = nil;
  self.routeInfo = nil;
  self.pairedEarly = nil;
  self.lateError = nil;
  self.attestationDevice = NULL;
}

- (void)settleConnect:(NSDictionary *)result error:(NSError *)error code:(NSString *)code message:(NSString *)message {
  RCTPromiseResolveBlock res = self.connectResolve;
  RCTPromiseRejectBlock rej = self.connectReject;
  self.connectResolve = nil;
  self.connectReject = nil;
  if (!res || !rej) { return; }
  if (result) { res(result); } else { TuyaMatterReject(rej, error, code, message); }
}

- (void)settleCommission:(NSDictionary *)result error:(NSError *)error code:(NSString *)code message:(NSString *)message {
  RCTPromiseResolveBlock res = self.commissionResolve;
  RCTPromiseRejectBlock rej = self.commissionReject;
  self.commissionResolve = nil;
  self.commissionReject = nil;
  if (!res || !rej) { return; }
  if (result) { res(result); } else { TuyaMatterReject(rej, error, code, message); }
}

- (NSString *)typeNameFor:(ThingSmartActivatorDeviceModel *)dev {
  ThingMatterDeviceModel *md = TuyaMatterDeviceOf(dev);
  if (md && md.deviceType != ThingMatterDeviceTypeUnknown) { return TuyaMatterTypeName(md.deviceType); }
  return self.routeInfo ? TuyaMatterRouteTypeName(self.routeInfo.deviceType) : @"unknown";
}

// iOS không lộ ip/port của phiên → "" / 0. accessType suy từ isThingMatter (0 = Tuya, 1 = bên thứ 3) như Android.
- (NSDictionary *)connectResultFor:(ThingSmartActivatorDeviceModel *)dev {
  ThingMatterDeviceModel *md = TuyaMatterDeviceOf(dev);
  ThingMatterSetupPayload *p = md.payload ?: (TuyaMatterPayloadOf(dev) ?: TuyaMatterPayloadOf(self.setupDevice));
  BOOL isThing = self.routeInfo ? self.routeInfo.isThingDevice : (md ? md.isThingDevice : [dev isThingDevice]);
  NSString *type = [self typeNameFor:dev];
  NSString *pid = md.thingProductId.length ? md.thingProductId
                : (p.thingProductId.length ? p.thingProductId : (dev.productId ?: @""));
  NSString *gw = md.gatewayId.length ? md.gatewayId : [dev deviceScanThreadGateway];
  return @{ @"discoveryType": [type isEqualToString:@"onNetwork"] ? @"mDNS" : @"BLE",
            @"ipAddress": @"",
            @"port": @0,
            @"thingProductId": pid ?: @"",
            @"accessType": @(isThing ? 0 : 1),
            @"isThingMatter": @(isThing),
            @"nodeId": @(md.nodeId),
            @"gwId": gw ?: @"" };
}

// ---------- ThingSmartActivatorDeviceExpandDelegate (Matter) ----------
- (void)matterDeviceDiscoveryed:(ThingMatterDeviceDiscoveriedType *)typeModel {
  TuyaMatterOnMain(^{
    self.routeInfo = typeModel;
    [self emit:@"onMatterDeviceFound" body:@{ @"dataJson": TuyaMatterJson(@{
      @"source": @"connect",
      @"isThingMatter": @(typeModel.isThingDevice),
      @"deviceType": TuyaMatterRouteTypeName(typeModel.deviceType),
      @"routingType": @(typeModel.routingType),
    }) }];
  });
}

- (void)matterCommissioningSessionEstablishmentComplete:(ThingSmartActivatorDeviceModel *)deviceModel {
  TuyaMatterOnMain(^{
    self.sessionDevice = deviceModel;
    [self settleConnect:[self connectResultFor:deviceModel] error:nil code:nil message:nil];
  });
}

- (void)matterDeviceAttestation:(void *)device error:(NSError *)error {
  NSInteger code = error.code;
  TuyaMatterOnMain(^{
    self.attestationDevice = device;
    [self emit:@"onMatterAttestation" body:@{ @"code": @(code) }];
  });
}

// ---------- ThingSmartActivatorActiveDelegate ----------
- (void)activatorService:(id<ThingSmartActivatorActiveProtocol>)service
           activatorType:(ThingSmartActivatorTypeModel *)type
       didReceiveDevices:(NSArray<ThingSmartActivatorDeviceModel *> *)devices
                   error:(ThingSmartActivatorErrorModel *)errorModel {
  if (type.type != ThingSmartActivatorTypeMatter) { return; }
  TuyaMatterOnMain(^{ [self handleActiveDevices:devices error:errorModel]; });
}

- (void)handleActiveDevices:(NSArray<ThingSmartActivatorDeviceModel *> *)devices
                      error:(ThingSmartActivatorErrorModel *)errorModel {
  self.activeStarted = NO;
  self.attestationDevice = NULL;
  if (errorModel) {
    NSError *e = errorModel.error;
    if (self.commissionReject) {
      [self settleCommission:nil error:e code:@"matter_commission_error" message:@"Matter commissioning failed."];
    } else if (self.connectReject) {
      [self settleConnect:nil error:e code:@"matter_connect_error" message:@"Matter connect failed."];
    } else {
      self.lateError = e; // vd. SDK timeout khi user chưa kịp gọi commissionDevice
      [self emitError:(e ? [@(e.code) stringValue] : @"matter_activator_error")
              message:(e.localizedDescription ?: @"Matter activation failed.")];
    }
    self.sessionDevice = nil;
    return;
  }
  ThingSmartActivatorDeviceModel *dev = devices.firstObject;
  NSDictionary *paired = dev ? TuyaMatterPaired(dev) : @{ @"devId": @"", @"name": @"", @"productId": @"" };
  if (self.commissionReject) {
    [self settleCommission:paired error:nil code:nil message:nil];
    [self resetSession];
  } else {
    // Hoàn tất mà không cần bước commission → connect trả kết quả, commissionDevice trả thiết bị ngay.
    self.pairedEarly = paired;
    if (self.connectReject) { [self settleConnect:[self connectResultFor:dev] error:nil code:nil message:nil]; }
  }
}

// ---------- ThingSmartActivatorSearchDelegate (auto-discovery) ----------
- (void)activatorService:(id<ThingSmartActivatorSearchProtocol>)service
            activatorType:(ThingSmartActivatorTypeModel *)type
             didFindDevice:(ThingSmartActivatorDeviceModel *)device
                     error:(ThingSmartActivatorErrorModel *)errorModel {
  if (type.type != ThingSmartActivatorTypeMatter) { return; }
  if (errorModel) {
    NSError *e = errorModel.error;
    TuyaMatterOnMain(^{
      [self emitError:(e ? [@(e.code) stringValue] : @"matter_discovery_error")
              message:(e.localizedDescription ?: @"Matter discovery failed.")];
    });
    return;
  }
  if (!device) { return; }
  ThingMatterDeviceModel *md = TuyaMatterDeviceOf(device);
  ThingMatterSetupPayload *p = md.payload ?: TuyaMatterPayloadOf(device);
  NSString *json = TuyaMatterJson(@{
    @"source": @"discovery",
    @"uniqueId": device.uniqueID ?: @"",
    @"name": device.name ?: @"",
    @"iconUrl": device.iconUrl ?: @"",
    @"productId": device.productId ?: @"",
    @"deviceType": md ? TuyaMatterTypeName(md.deviceType) : @"unknown",
    @"isThingMatter": @(md ? md.isThingDevice : [device isThingDevice]),
    @"vendorId": p.vendorID ?: @0,
    @"matterProductId": p.productID ?: @0,
    @"discriminator": p.discriminator ?: @0,
  });
  TuyaMatterOnMain(^{ [self emit:@"onMatterDeviceFound" body:@{ @"dataJson": json }]; });
}

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaMatterSpecJSI>(params);
}

@end
