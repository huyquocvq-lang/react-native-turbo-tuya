#import "TuyaDevice.h"
#import "TuyaReject.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaDevice (iOS) - WIRED: DP control (publishDps + mode + channels + awaitAck + cache), snapshot/getDps/online,
// queryDp, rename/remove/resetFactory, Wi-Fi signal, cloud (MQTT) state, BLE connect/disconnect/local-online,
// and the status listener (ThingSmartDeviceDelegate device:dpsUpdate:/deviceInfoUpdate: → emit onDeviceStatus).
// Verbatim: docs/research/tuya-home-sdk-device-control.md (section iOS); selector mới verify với header Pods
// (ThingSmartDevice.h, ThingSmartCommunication.h, ThingSmartBLEManager+Biz.h, ThingSmartMQTTChannel.h).
// Method mới reject qua TuyaReject.h với mã Tuya THẬT (NSError.code) - không thay bằng literal.

// Reject mang mã lỗi Tuya THẬT: NSError.code + localizedDescription; SDK không trả NSError → fallback nói rõ.
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

static void TuyaRejectNoDevice(RCTPromiseRejectBlock reject, NSString *devId) {
  TuyaRejectWithDomain(reject, @"no_device", [NSString stringWithFormat:@"Device not found: %@", devId], @"sdk");
}

// Tên kênh JS → ThingCommunicationType (cùng số với Android CommunicationEnum). Số ("3" / 3) đi thẳng cho SDK tự kiểm.
static NSNumber *TuyaChannelType(id raw) {
  if ([raw isKindOfClass:[NSNumber class]]) return @([raw integerValue]);
  if (![raw isKindOfClass:[NSString class]]) return nil;
  NSString *name = [[(NSString *)raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                    lowercaseString];
  if (name.length == 0) return nil;
  NSScanner *scanner = [NSScanner scannerWithString:name];
  NSInteger number = 0;
  if ([scanner scanInteger:&number] && scanner.isAtEnd) return @(number);
  static NSDictionary<NSString *, NSNumber *> *map;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    map = @{
      @"lan": @(ThingCommunicationTypeLAN), @"local": @(ThingCommunicationTypeLAN),
      @"mqtt": @(ThingCommunicationTypeMQTT), @"cloud": @(ThingCommunicationTypeMQTT),
      @"internet": @(ThingCommunicationTypeMQTT),
      @"http": @(ThingCommunicationTypeHTTP),
      @"ble": @(ThingCommunicationTypeBLE), @"bluetooth": @(ThingCommunicationTypeBLE),
      @"sigmesh": @(ThingCommunicationTypeSIGMesh), @"sig_mesh": @(ThingCommunicationTypeSIGMesh),
      @"mesh": @(ThingCommunicationTypeBLEMesh), @"blemesh": @(ThingCommunicationTypeBLEMesh),
      @"ble_mesh": @(ThingCommunicationTypeBLEMesh), @"thing_mesh": @(ThingCommunicationTypeBLEMesh),
      @"beacon": @(ThingCommunicationTypeBLEBeacon),
      @"matter": @(ThingCommunicationTypeMatter),
      @"yumqtt": @(ThingCommunicationTypeYuNetMqtt), @"yu_mqtt": @(ThingCommunicationTypeYuNetMqtt),
      @"cloudmode": @(ThingCommunicationTypeCloudMode), @"cloud_mode": @(ThingCommunicationTypeCloudMode),
    };
  });
  return map[name];
}

// Thiết bị trả signal qua MQTT; header không cam kết timeout (Android: SDK không có) → tự chặn để promise không treo.
static const double kTuyaWifiSignalTimeoutSec = 10;

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

// channels theo thứ tự ưu tiên (vd ['ble','cloud']) → mảng ThingCommunicationType cho
// publishDps:communicationTypes:. 'cloud' = MQTT (1). Tên lạ → reject sớm (không đoán).
- (void)publishDpsWithChannels:(NSString *)devId
                       dpsJson:(NSString *)dpsJson
                      channels:(NSArray *)channels
                       resolve:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { TuyaRejectNoDevice(reject, devId); return; }
  NSMutableArray<NSNumber *> *types = [NSMutableArray array];
  for (id channel in channels) {
    NSNumber *type = TuyaChannelType(channel);
    if (!type) {
      TuyaRejectWithDomain(reject, @"invalid_channel",
          [NSString stringWithFormat:@"Unknown channel '%@'. Use lan, mqtt|cloud, http, ble, sigmesh, mesh, beacon, "
                                     @"matter, yumqtt, cloudmode or a numeric ThingCommunicationType.", channel],
          @"sdk");
      return;
    }
    [types addObject:type];
  }
  if (types.count == 0) {
    TuyaRejectWithDomain(reject, @"invalid_channel",
                         @"channels is empty - pass at least one channel, e.g. ['ble','cloud'].", @"sdk");
    return;
  }
  [dev publishDps:TuyaParseDps(dpsJson)
communicationTypes:types
          success:^{ resolve(nil); }
          failure:^(NSError *e) {
    TuyaRejectNSError(reject, e, @"publish_dps_error", @"publishDps with channel orders failed.");
  }];
}

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

// Cách "Query DP Data" của doc iOS (= Android getDp): gửi {dpId: null} → thiết bị báo lại giá trị qua
// device:dpsUpdate: → onDeviceStatus (cần registerDeviceListener). resolve = "đã gửi", KHÔNG trả giá trị.
- (void)queryDp:(NSString *)devId
           dpId:(NSString *)dpId
        resolve:(RCTPromiseResolveBlock)resolve
         reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = self.devices[devId] ?: [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { TuyaRejectNoDevice(reject, devId); return; }
  if (dpId.length == 0) { TuyaRejectWithDomain(reject, @"invalid_argument", @"dpId is empty.", @"sdk"); return; }
  [dev publishDps:@{ dpId: [NSNull null] }
             mode:ThingDevicePublishModeAuto
          success:^{ resolve(nil); }
          failure:^(NSError *e) { TuyaRejectNSError(reject, e, @"query_dp_error", @"Query DP failed."); }];
}

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

// = Android getServerInstance().isServerConnect: kênh MQTT mặc định (uniTag default) của SDK đã Connected chưa.
- (void)isCloudConnected:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  resolve(@([[ThingSmartMQTTChannel sharedInstance] connectState] == ThingSmartMqttConnectStateConnected));
}

// Low-power: DP nằm cache cloud chờ thiết bị thức. validity 1…172800s (SDK tự kiểm, lỗi trả qua NSError);
// dpCacheType 0 = thiết bị tự kéo, 1 = cloud đẩy.
- (void)sendCacheDps:(NSString *)devId
             dpsJson:(NSString *)dpsJson
         validitySec:(double)validitySec
         dpCacheType:(double)dpCacheType
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { TuyaRejectNoDevice(reject, devId); return; }
  [dev sendCacheDps:TuyaParseDps(dpsJson)
           validity:(NSUInteger)MAX(validitySec, 0)
        dpCacheType:(NSUInteger)MAX(dpCacheType, 0)
            success:^(id result) {
    // ThingSuccessID: thường là NSNumber(BOOL); kiểu khác/không có ⇒ coi success = YES (khớp Android).
    resolve(@([result respondsToSelector:@selector(boolValue)] ? [result boolValue] : YES));
  } failure:^(NSError *e) {
    TuyaRejectNSError(reject, e, @"send_cache_dps_error", @"sendCacheDps failed.");
  }];
}

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

// Khôi phục cài đặt gốc: thiết bị reset + gỡ khỏi tài khoản (khác removeDevice chỉ gỡ).
- (void)resetFactory:(NSString *)devId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { TuyaRejectNoDevice(reject, devId); return; }
  [dev resetFactory:^{ resolve(nil); }
            failure:^(NSError *e) { TuyaRejectNSError(reject, e, @"reset_factory_error", @"resetFactory failed."); }];
}

// RSSI (dBm, số âm vd -45) do thiết bị trả qua MQTT. queryWifiSignalStrengthWithSuccess: = bản block của
// getWifiSignalStrengthWithSuccess: + delegate device:signal: (đã xem SDK): callback lưu TRÊN instance ⇒ phải giữ
// instance sống tới lúc settle (`holder`), rồi thả để phá vòng giữ instance → callback → holder.
- (void)getWifiSignal:(NSString *)devId
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { TuyaRejectNoDevice(reject, devId); return; }
  // Mọi nhánh settle trên main queue ⇒ cờ `settled` không cần lock (như publishDpsAwaitAck).
  __block BOOL settled = NO;
  __block ThingSmartDevice *holder = dev;
  void (^settle)(dispatch_block_t) = ^(dispatch_block_t finish) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (settled) { return; }
      settled = YES;
      holder = nil;
      finish();
    });
  };
  dispatch_async(dispatch_get_main_queue(), ^{
    [holder queryWifiSignalStrengthWithSuccess:^(int result) {
      settle(^{ resolve(@(result)); });
    } failure:^(NSError *e) {
      settle(^{ TuyaRejectNSError(reject, e, @"wifi_signal_error", @"Wi-Fi signal query failed."); });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTuyaWifiSignalTimeoutSec * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      settle(^{
        TuyaRejectWithDomain(reject, @"wifi_signal_timeout",
            [NSString stringWithFormat:@"Device did not report its Wi-Fi signal within %.0fs.", kTuyaWifiSignalTimeoutSec],
            @"sdk");
      });
    });
  });
}

// ---------- BLE local control (ThingSmartBLEManager, theo deviceModel.uuid) ----------
// connectBLEWithUUID:productKey: là API "kết nối thiết bị offline" của doc; failure là ThingFailureHandler
// (block rỗng) ⇒ SDK không cho mã lỗi → dùng literal và nói rõ.
- (void)bleConnect:(NSString *)devId
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { TuyaRejectNoDevice(reject, devId); return; }
  ThingSmartDeviceModel *m = dev.deviceModel;
  if (m.uuid.length == 0) {
    TuyaRejectWithDomain(reject, @"ble_uuid_missing", @"Device has no uuid - cannot connect over BLE.", @"sdk");
    return;
  }
  ThingSmartBLEManager *ble = [ThingSmartBLEManager sharedInstance];
  if ([ble deviceStatueWithUUID:m.uuid]) { resolve(nil); return; } // đã kết nối local
  [ble connectBLEWithUUID:m.uuid
               productKey:(m.productId ?: @"")
                  success:^{ resolve(nil); }
                  failure:^{
    TuyaRejectWithDomain(reject, @"ble_connect_error", @"BLE connect failed (the SDK returned no error details).", @"sdk");
  }];
}

- (void)bleDisconnect:(NSString *)devId
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { TuyaRejectNoDevice(reject, devId); return; }
  NSString *uuid = dev.deviceModel.uuid;
  if (uuid.length == 0) {
    TuyaRejectWithDomain(reject, @"ble_uuid_missing", @"Device has no uuid - cannot disconnect BLE.", @"sdk");
    return;
  }
  [[ThingSmartBLEManager sharedInstance] disconnectBLEWithUUID:uuid
                                                       success:^{ resolve(nil); }
                                                       failure:^(NSError *e) {
    TuyaRejectNSError(reject, e, @"ble_disconnect_error", @"BLE disconnect failed.");
  }];
}

// Kết nối BLE local (doc: combo device isOnline=YES mà hàm này NO ⇒ đang đi Wi-Fi, không phải BLE).
- (void)isBleLocalOnline:(NSString *)devId
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  ThingSmartDevice *dev = [ThingSmartDevice deviceWithDeviceId:devId];
  if (!dev) { TuyaRejectNoDevice(reject, devId); return; }
  NSString *uuid = dev.deviceModel.uuid;
  resolve(@(uuid.length > 0 && [[ThingSmartBLEManager sharedInstance] deviceStatueWithUUID:uuid]));
}

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
