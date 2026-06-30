#import "TuyaPairing.h"

// TuyaPairing (iOS) — TODO-reject (implement bằng ThingSmartActivator/ThingSmartBLEManager trên Xcode).
// Event onPairingProgress/onBleScan phát qua TuyaEventEmitter: [self emit:name body:...] khi impl xong.
// Combo (BLE+Wi-Fi): ThingSmartBLEWifiActivator startConfigBLEWifiDeviceWithUUID:homeId:productId:ssid:password:timeout:...
// Auto-token Wi-Fi: [[ThingSmartActivator sharedInstance] getTokenWithHomeId:...] → startConfigWiFi:ssid:password:token:timeout:.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — implement bằng ThingSmartActivator/BLEManager trên Xcode.", what],
         nil);
}

@implementation TuyaPairing

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents { return @[@"onPairingProgress", @"onBleScan"]; }

- (void)getPairingToken:(double)homeId
                resolve:(RCTPromiseResolveBlock)resolve
                 reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getPairingToken", reject); }

- (void)startWifiPairing:(NSString *)mode
                    ssid:(NSString *)ssid
                password:(NSString *)password
                   token:(NSString *)token
              timeoutSec:(double)timeoutSec
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startWifiPairing", reject); }

- (void)stopWifiPairing {}

// Khi impl scan: [self emit:@"onBleScan" body:@{...}]; pairing progress: [self emit:@"onPairingProgress" body:@{...}].
- (void)startBleScan:(double)timeoutSec {}
- (void)stopBleScan {}

- (void)startBlePairing:(double)homeId
                   uuid:(NSString *)uuid
              productId:(NSString *)productId
                address:(NSString *)address
             deviceType:(double)deviceType
             timeoutSec:(double)timeoutSec
                resolve:(RCTPromiseResolveBlock)resolve
                 reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startBlePairing", reject); }

// ---------- Combo / dual-mode (BLE + Wi-Fi) ----------
- (void)startBleWifiPairing:(double)homeId
                       uuid:(NSString *)uuid
                       ssid:(NSString *)ssid
                   password:(NSString *)password
                 timeoutSec:(double)timeoutSec
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startBleWifiPairing", reject); }

- (void)stopBleWifiPairing:(NSString *)uuid {}

// ---------- Auto-token Wi-Fi (EZ/AP) ----------
- (void)startWifiPairingAuto:(double)homeId
                        mode:(NSString *)mode
                        ssid:(NSString *)ssid
                    password:(NSString *)password
                  timeoutSec:(double)timeoutSec
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"startWifiPairingAuto", reject); }

// ---------- P3: pairing nâng cao (ThingSmartActivator: activeSubDeviceWithGwId/activeGatewayDeviceWithGwId/parseQRCode) ----------
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

- (void)destroyActivator {}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) — không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaPairingSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaPairing"; }

@end
