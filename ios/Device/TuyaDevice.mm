#import "TuyaDevice.h"

// TuyaDevice (iOS) — TODO-reject (implement bằng ThingSmartDevice + ThingSmartDeviceDelegate trên Xcode).
// Android là nền tảng wired đầy đủ B4; iOS device-control là effort riêng (selector verbatim trong
// docs/research/tuya-home-sdk-device-control.md). Event onDeviceStatus phát qua TuyaEventEmitter khi impl.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-device-control.md.", what],
         nil);
}

@implementation TuyaDevice

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents { return @[@"onDeviceStatus"]; }

// ---------- DP control ----------
- (void)publishDps:(NSString *)devId
           dpsJson:(NSString *)dpsJson
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"publishDps", reject); }

- (void)publishDpsWithMode:(NSString *)devId
                   dpsJson:(NSString *)dpsJson
                      mode:(NSString *)mode
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"publishDpsWithMode", reject); }

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
        reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getDps", reject); }

- (void)queryDp:(NSString *)devId
           dpId:(NSString *)dpId
        resolve:(RCTPromiseResolveBlock)resolve
         reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"queryDp", reject); }

- (void)getDeviceSnapshot:(NSString *)devId
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getDeviceSnapshot", reject); }

- (void)isDeviceOnline:(NSString *)devId
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"isDeviceOnline", reject); }

- (void)isCloudConnected:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"isCloudConnected", reject); }

- (void)sendCacheDps:(NSString *)devId
             dpsJson:(NSString *)dpsJson
         validitySec:(double)validitySec
         dpCacheType:(double)dpCacheType
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"sendCacheDps", reject); }

// ---------- Device listener (delegate device:dpsUpdate: → [self emit:@"onDeviceStatus" ...] khi impl) ----------
- (void)registerDeviceListener:(NSString *)devId {}
- (void)unregisterDeviceListener:(NSString *)devId {}

// ---------- Device management ----------
- (void)renameDevice:(NSString *)devId
                name:(NSString *)name
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"renameDevice", reject); }

- (void)removeDevice:(NSString *)devId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"removeDevice", reject); }

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

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) — không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaDeviceSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaDevice"; }

@end
