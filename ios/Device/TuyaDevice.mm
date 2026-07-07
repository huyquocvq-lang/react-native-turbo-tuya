#import "TuyaDevice.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaDevice (iOS) - WIRED: DP control (publishDps + mode), snapshot/getDps/online, rename/remove, and the
// status listener (ThingSmartDeviceDelegate device:dpsUpdate:/deviceInfoUpdate: → emit onDeviceStatus).
// Verbatim: docs/research/tuya-home-sdk-device-control.md (section iOS).
// TODO (selector/feature chưa verbatim trên iOS): queryDp, isCloudConnected, resetFactory, getWifiSignal,
//   publishDpsWithChannels, publishDpsAwaitAck, sendCacheDps, bleConnect/bleDisconnect/isBleLocalOnline.
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

- (void)publishDpsAwaitAck:(NSString *)devId
                   dpsJson:(NSString *)dpsJson
                 timeoutMs:(double)timeoutMs
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"publishDpsAwaitAck", reject); }

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
  // iOS ThingSmartDeviceModel: dps/productId/isOnline. isLocalOnline + schema/dpCodes serialize chưa wire → để rỗng.
  resolve(@{
    @"devId": m.devId ?: devId,
    @"productId": m.productId ?: @"",
    @"dpsJson": TuyaJson(m.dps ?: @{}),
    @"isOnline": @(m.isOnline),
    @"isLocalOnline": @(m.isOnline),
    @"schemaJson": @"",
    @"dpCodesJson": @"",
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
