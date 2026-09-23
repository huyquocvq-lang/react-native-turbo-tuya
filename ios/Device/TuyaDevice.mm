#import "TuyaDevice.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaDevice (iOS) - WIRED: DP control (publishDps + mode + awaitAck), snapshot/getDps/online, rename/remove,
// and the status listener (ThingSmartDeviceDelegate device:dpsUpdate:/deviceInfoUpdate: → emit onDeviceStatus).
// Verbatim: docs/research/tuya-home-sdk-device-control.md (section iOS).
// TODO (selector/feature chưa verbatim trên iOS): queryDp, isCloudConnected, resetFactory, getWifiSignal,
//   publishDpsWithChannels, sendCacheDps, bleConnect/bleDisconnect/isBleLocalOnline.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire - xem docs/research/tuya-home-sdk-device-control.md.", what],
         nil);
}

static NSDictionary *TuyaParseDps(NSString *json) {
  NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
  id obj = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
  return [obj isKindOfClass:[NSDictionary class]] ? obj : @{};
}

static NSString *TuyaJson(id obj) {
  if (![obj isKindOfClass:[NSDictionary class]] && ![obj isKindOfClass:[NSArray class]]) return @"{}";
  if (![NSJSONSerialization isValidJSONObject:obj]) return @"{}";
  NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"{}";
}

// timeoutMs <= 0 từ JS → dùng mức này (khớp DEFAULT_ACK_TIMEOUT của Android).
static const double kTuyaDefaultAckTimeoutMs = 8000;

// Chờ ack cho publishDpsAwaitAck. Nghe dpsUpdate trên một ThingSmartDevice RIÊNG (như Android dùng
// newDeviceInstance riêng) nên không đè delegate của listener bền ở registerDeviceListener: mỗi instance
// tự nhận notification DP của SDK. `delegate` của ThingSmartDevice là weak ⇒ waiter giữ device, còn
// block publish/timeout giữ waiter tới khi settle.
@interface TuyaDpsAckWaiter : NSObject <ThingSmartDeviceDelegate>
@property (nonatomic, strong) ThingSmartDevice *device;
@property (nonatomic, copy) NSSet<NSString *> *dpIds; // rỗng ⇒ update nào cũng tính là ack (như Android)
@property (nonatomic, copy) void (^onAck)(void);
@end

@implementation TuyaDpsAckWaiter
// CHỈ implement bản không dpsTime: header ghi rõ có `device:dpsUpdate:dpsTime:` thì SDK bỏ qua bản này.
- (void)device:(ThingSmartDevice *)device dpsUpdate:(NSDictionary *)dps {
  BOOL matched = self.dpIds.count == 0;
  for (id key in dps) {
    if ([self.dpIds containsObject:[NSString stringWithFormat:@"%@", key]]) { matched = YES; break; }
  }
  if (matched && self.onAck) { self.onAck(); }
}
@end

@interface TuyaDevice () <ThingSmartDeviceDelegate>
// Giữ instance có delegate để nhận dpsUpdate; gỡ ở unregister/invalidate.
@property (nonatomic, strong) NSMutableDictionary<NSString *, ThingSmartDevice *> *devices;
@end

@implementation TuyaDevice

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents { return @[@"onDeviceStatus"]; }

- (NSMutableDictionary<NSString *, ThingSmartDevice *> *)devices {
  if (!_devices) { _devices = [NSMutableDictionary dictionary]; }
  return _devices;
}

// ---------- DP control ----------
- (void)publishDps:(NSString *)devId
           dpsJson:(NSString *)dpsJson
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { reject(@"no_device", @"Không tìm thấy thiết bị", nil); return; }
  [dev publishDps:TuyaParseDps(dpsJson)
          success:^{ resolve(nil); }
          failure:^(NSError *e) { reject(@"publish_dps_error", e.localizedDescription, e); }];
}

- (void)publishDpsWithMode:(NSString *)devId
                   dpsJson:(NSString *)dpsJson
                      mode:(NSString *)mode
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { reject(@"no_device", @"Không tìm thấy thiết bị", nil); return; }
  ThingDevicePublishMode m = ThingDevicePublishModeAuto;
  if ([mode.lowercaseString isEqualToString:@"local"]) m = ThingDevicePublishModeLocal;
  else if ([mode.lowercaseString isEqualToString:@"internet"]) m = ThingDevicePublishModeInternet;
  [dev publishDps:TuyaParseDps(dpsJson)
             mode:m
          success:^{ resolve(nil); }
          failure:^(NSError *e) { reject(@"publish_dps_error", e.localizedDescription, e); }];
}

- (void)publishDpsWithChannels:(NSString *)devId
                       dpsJson:(NSString *)dpsJson
                      channels:(NSArray *)channels
                       resolve:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"publishDpsWithChannels", reject); }

// Resolve khi dpsUpdate KHỚP dpId vừa publish (success của publishDps chỉ = "đã gửi"). Mirror Android.
- (void)publishDpsAwaitAck:(NSString *)devId
                   dpsJson:(NSString *)dpsJson
                 timeoutMs:(double)timeoutMs
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { reject(@"no_device", @"Không tìm thấy thiết bị", nil); return; }
  NSDictionary *dps = TuyaParseDps(dpsJson);
  NSMutableSet<NSString *> *dpIds = [NSMutableSet set];
  for (id key in dps) { [dpIds addObject:[NSString stringWithFormat:@"%@", key]]; }
  double timeout = timeoutMs > 0 ? timeoutMs : kTuyaDefaultAckTimeoutMs;

  TuyaDpsAckWaiter *waiter = [TuyaDpsAckWaiter new];
  waiter.device = dev;
  waiter.dpIds = dpIds;

  // Mọi nhánh (ack / publish lỗi / timeout) settle trên main queue ⇒ cờ `settled` không cần lock.
  // `holder` giữ waiter sống tới lúc settle rồi thả ra - phá vòng giữ waiter → onAck → settle → waiter.
  __block BOOL settled = NO;
  __block TuyaDpsAckWaiter *holder = waiter;
  void (^settle)(dispatch_block_t) = ^(dispatch_block_t finish) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (settled) { return; }
      settled = YES;
      holder.device.delegate = nil;
      holder = nil;
      finish();
    });
  };
  waiter.onAck = ^{ settle(^{ resolve(nil); }); };

  dispatch_async(dispatch_get_main_queue(), ^{
    dev.delegate = waiter; // gắn TRƯỚC khi publish để không lỡ echo về nhanh
    [dev publishDps:dps
            success:^{ /* chờ dpsUpdate */ }
            failure:^(NSError *e) {
              settle(^{ reject(@"publish_dps_error", e.localizedDescription, e); });
            }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
      settle(^{
        reject(@"ack_timeout",
               [NSString stringWithFormat:@"Không nhận dpsUpdate trong %.0fms", timeout], nil);
      });
    });
  });
}

- (void)getDps:(NSString *)devId
       resolve:(RCTPromiseResolveBlock)resolve
        reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { reject(@"no_device", @"Không tìm thấy thiết bị", nil); return; }
  resolve(TuyaJson(dev.deviceModel.dps ?: @{}));
}

- (void)queryDp:(NSString *)devId
           dpId:(NSString *)dpId
        resolve:(RCTPromiseResolveBlock)resolve
         reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"queryDp", reject); }

- (void)getDeviceSnapshot:(NSString *)devId
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { reject(@"no_device", @"Không tìm thấy thiết bị", nil); return; }
  ThingSmartDeviceModel *m = dev.deviceModel;

  // schemaArray (ThingSmartSchemaModel: dpId/code/name/mode/type/property) → dựng 2 thứ app cần:
  //   · dpCodes {dpId: code} → JS resolve DP theo CODE chuẩn thay vì hardcode id (services/dp.ts).
  //   · schema đầy đủ kèm property (min/max/step/scale/unit) → render đúng biên (services/deviceSchema.ts).
  // Trước đây cả hai trả rỗng ⇒ JS luôn rơi về DP placeholder ⇒ map sai DP với bồn thật.
  NSMutableDictionary *dpCodes = [NSMutableDictionary dictionary];
  NSMutableArray *schema = [NSMutableArray array];
  for (ThingSmartSchemaModel *s in m.schemaArray) {
    if (s.dpId.length > 0 && s.code.length > 0) dpCodes[s.dpId] = s.code;
    NSMutableDictionary *entry = [@{
      @"dpId": s.dpId ?: @"",
      @"code": s.code ?: @"",
      @"name": s.name ?: @"",
      @"mode": s.mode ?: @"", // ro / rw / wr
      @"type": s.type ?: @"",
    } mutableCopy];
    ThingSmartSchemaPropertyModel *p = s.property;
    if (p) {
      entry[@"property"] = @{
        @"type": p.type ?: @"",
        @"unit": p.unit ?: @"",
        @"min": @(p.min),
        @"max": @(p.max),
        @"step": @(p.step),
        @"scale": @(p.scale),
        @"range": p.range ?: @[],
        @"label": p.label ?: @[],
      };
    }
    [schema addObject:entry];
  }

  // Toàn bộ thông tin model SDK trả về - CHỈ để log/chẩn đoán (JS in ra, không dùng cho logic).
  NSDictionary *raw = @{
    @"devId": m.devId ?: @"",
    @"name": m.name ?: @"",
    @"iconUrl": m.iconUrl ?: @"",
    @"productId": m.productId ?: @"",
    @"productVer": m.productVer ?: @"",
    @"verSw": m.verSw ?: @"",
    @"uuid": m.uuid ?: @"",
    @"mac": m.mac ?: @"",
    @"gwType": m.gwType ?: @"",
    @"runtimeEnv": m.runtimeEnv ?: @"",
    @"timezoneId": m.timezoneId ?: @"",
    @"isOnline": @(m.isOnline),
    @"isCloudOnline": @(m.isCloudOnline),
    @"isLocalOnline": @(m.isLocalOnline),
    @"isShare": @(m.isShare),
    @"supportGroup": @(m.supportGroup),
    @"homeId": @(m.homeId),
    @"roomId": @(m.roomId),
    @"capability": @(m.capability),
    @"attribute": @(m.attribute),
    @"ability": @(m.ability),
    @"pv": @(m.pv),
    @"lpv": @(m.lpv),
    @"bv": @(m.bv),
    @"dps": m.dps ?: @{},
    @"dpsTime": m.dpsTime ?: @{},
    @"dpName": m.dpName ?: @{},
    @"schemaCount": @(m.schemaArray.count),
  };

  resolve(@{
    @"devId": m.devId ?: devId,
    @"productId": m.productId ?: @"",
    @"dpsJson": TuyaJson(m.dps ?: @{}),
    @"isOnline": @(m.isOnline),
    @"isLocalOnline": @(m.isLocalOnline),
    // schemaArray rỗng (hiếm) → rơi về chuỗi schema thô của SDK, đừng trả rỗng.
    @"schemaJson": schema.count > 0 ? TuyaJson(schema) : (m.schema ?: @""),
    @"dpCodesJson": TuyaJson(dpCodes),
    @"rawJson": TuyaJson(raw),
  });
}

- (void)isDeviceOnline:(NSString *)devId
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  resolve(@(dev.deviceModel.isOnline));
}

- (void)isCloudConnected:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"isCloudConnected", reject); }

- (void)sendCacheDps:(NSString *)devId
             dpsJson:(NSString *)dpsJson
         validitySec:(double)validitySec
         dpCacheType:(double)dpCacheType
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"sendCacheDps", reject); }

// ---------- Device listener (delegate → emit onDeviceStatus) ----------
- (void)registerDeviceListener:(NSString *)devId {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { return; }
  dev.delegate = self;
  self.devices[devId] = dev;
}

- (void)unregisterDeviceListener:(NSString *)devId {
  ThingSmartDevice *dev = self.devices[devId];
  dev.delegate = nil;
  [self.devices removeObjectForKey:devId];
}

- (void)device:(ThingSmartDevice *)device dpsUpdate:(NSDictionary *)dps {
  [self emit:@"onDeviceStatus" body:@{ @"devId": device.deviceModel.devId ?: @"",
                                       @"dpsJson": TuyaJson(dps ?: @{}) }];
}

- (void)deviceInfoUpdate:(ThingSmartDevice *)device {
  [self emit:@"onDeviceStatus" body:@{ @"devId": device.deviceModel.devId ?: @"",
                                       @"isOnline": @(device.deviceModel.isOnline) }];
}

// ---------- Device management ----------
- (void)renameDevice:(NSString *)devId
                name:(NSString *)name
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { reject(@"no_device", @"Không tìm thấy thiết bị", nil); return; }
  [dev updateName:name
          success:^{ resolve(nil); }
          failure:^(NSError *e) { reject(@"rename_error", e.localizedDescription, e); }];
}

- (void)removeDevice:(NSString *)devId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { reject(@"no_device", @"Không tìm thấy thiết bị", nil); return; }
  [dev remove:^{ resolve(nil); }
      failure:^(NSError *e) { reject(@"remove_error", e.localizedDescription, e); }];
}

- (void)resetFactory:(NSString *)devId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"resetFactory", reject); }

- (void)getWifiSignal:(NSString *)devId
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getWifiSignal", reject); }

// ---------- BLE local control ----------
- (void)bleConnect:(NSString *)devId
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"bleConnect", reject); }

- (void)bleDisconnect:(NSString *)devId
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"bleDisconnect", reject); }

- (void)isBleLocalOnline:(NSString *)devId
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"isBleLocalOnline", reject); }

- (void)dealloc {
  for (ThingSmartDevice *dev in _devices.allValues) { dev.delegate = nil; }
}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) - không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaDeviceSpecJSI>(params);
}

@end
