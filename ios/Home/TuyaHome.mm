#import "TuyaHome.h"
#import "TuyaReject.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaHome (iOS) - WIRED: home CRUD (create/list/detail/update/dismiss) + weather sketch/detail + change/status
// listeners (ThingSmartHomeManagerDelegate / ThingSmartHomeDelegate → emit onHomeChange).
// Verbatim selectors: docs/research/tuya-home-sdk-home-management.md (section A iOS). Weather detail verify trên
// header ThingSmartHome+Weather.h / ThingSmartWeatherOptionModel.h / ThingSmartWeatherModel.h (DeviceKit 5.14.6).
// ⚠️ Verify: ThingSmartHomeModel.role numeric (iOS ThingHomeRoleType có thể KHÁC scheme 2/1/0 của Android - chuẩn hoá sau);
//    tên delegate method cấp home (home:didAddDeivce: / didRemoveDeivce: / homeDidUpdateInfo:) - note đánh dấu cần verify.

// Reject mang mã lỗi Tuya THẬT: NSError.code + localizedDescription (giống TuyaPairing) - không gom về literal.
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

// ThingSmartHomeModel → HomeResult. role: raw iOS ThingHomeRoleType (⚠️ verify vs Android 2/1/0).
static NSDictionary *TuyaHomeMap(ThingSmartHomeModel *m) {
  return @{
    @"homeId": @(m.homeId),
    @"name": m.name ?: @"",
    @"role": @(m.role),
    @"admin": @(m.role != 0),
    @"lon": @(m.longitude),
    @"lat": @(m.latitude),
    @"geoName": m.geoName ?: @"",
  };
}

@interface TuyaHome () <ThingSmartHomeManagerDelegate, ThingSmartHomeDelegate>
@property (nonatomic, strong) ThingSmartHomeManager *homeManager;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, ThingSmartHome *> *homes;
@end

@implementation TuyaHome

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents { return @[@"onHomeChange"]; }

- (ThingSmartHomeManager *)homeManager {
  if (!_homeManager) { _homeManager = [[ThingSmartHomeManager alloc] init]; }
  return _homeManager;
}

- (NSMutableDictionary<NSNumber *, ThingSmartHome *> *)homes {
  if (!_homes) { _homes = [NSMutableDictionary dictionary]; }
  return _homes;
}

// Resolve a ThingSmartHome instance (nil-safe) for a given id.
- (ThingSmartHome *)homeOf:(double)homeId {
  return [ThingSmartHome homeWithHomeId:(long long)homeId];
}

// ---------- Home CRUD ----------
- (void)createHome:(NSString *)name
               lon:(double)lon
               lat:(double)lat
           geoName:(NSString *)geoName
             rooms:(NSArray *)rooms
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject {
  [self.homeManager addHomeWithName:name
                            geoName:geoName
                              rooms:rooms
                           latitude:lat
                          longitude:lon
                            success:^(long long homeId) {
    // Creator is the owner; return inputs + new id (no model fetch needed).
    resolve(@{ @"homeId": @(homeId), @"name": name ?: @"", @"role": @2, @"admin": @YES,
               @"lon": @(lon), @"lat": @(lat), @"geoName": geoName ?: @"" });
  } failure:^(NSError *e) { reject(@"create_home_error", e.localizedDescription, e); }];
}

- (void)getHomeList:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject {
  [self.homeManager getHomeListWithSuccess:^(NSArray<ThingSmartHomeModel *> *homes) {
    NSMutableArray *out = [NSMutableArray array];
    for (ThingSmartHomeModel *m in homes) { [out addObject:TuyaHomeMap(m)]; }
    resolve(out);
  } failure:^(NSError *e) { reject(@"home_list_error", e.localizedDescription, e); }];
}

- (void)getHomeDetail:(double)homeId
              resolve:(RCTPromiseResolveBlock)resolve
               reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [self homeOf:homeId];
  if (!home) { reject(@"no_home", @"Không tìm thấy home", nil); return; }
  [home getHomeDataWithSuccess:^(ThingSmartHomeModel *m) {
    resolve(TuyaHomeMap(m));
  } failure:^(NSError *e) { reject(@"home_detail_error", e.localizedDescription, e); }];
}

// Danh sách thiết bị của home: nạp home data rồi map home.deviceList (ThingSmartDeviceModel).
- (void)getHomeDeviceList:(double)homeId
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [self homeOf:homeId];
  if (!home) { reject(@"no_home", @"Không tìm thấy home", nil); return; }
  [home getHomeDataWithSuccess:^(ThingSmartHomeModel *m) {
    NSMutableArray *out = [NSMutableArray array];
    for (ThingSmartDeviceModel *d in home.deviceList) {
      [out addObject:@{
        @"devId": d.devId ?: @"",
        @"name": d.name ?: @"",
        @"productId": d.productId ?: @"",
        @"isOnline": @(d.isOnline),
        @"iconUrl": d.iconUrl ?: @"",
      }];
    }
    resolve(out);
  } failure:^(NSError *e) { reject(@"home_device_list_error", e.localizedDescription, e); }];
}

- (void)updateHome:(double)homeId
              name:(NSString *)name
               lon:(double)lon
               lat:(double)lat
           geoName:(NSString *)geoName
             rooms:(NSArray *)rooms
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [self homeOf:homeId];
  if (!home) { reject(@"no_home", @"Không tìm thấy home", nil); return; }
  // iOS updateHomeInfo không nhận rooms (room ops riêng); rooms bỏ qua ở đây.
  [home updateHomeInfoWithName:name
                       geoName:geoName
                      latitude:lat
                     longitude:lon
                       success:^{ resolve(nil); }
                       failure:^(NSError *e) { reject(@"update_home_error", e.localizedDescription, e); }];
}

- (void)dismissHome:(double)homeId
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [self homeOf:homeId];
  if (!home) { reject(@"no_home", @"Không tìm thấy home", nil); return; }
  [home dismissHomeWithSuccess:^{ resolve(nil); }
                       failure:^(NSError *e) { reject(@"dismiss_home_error", e.localizedDescription, e); }];
}

// ---------- Weather ----------
- (void)getHomeWeatherSketch:(double)homeId
                         lon:(double)lon
                         lat:(double)lat
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [self homeOf:homeId];
  if (!home) { reject(@"no_home", @"Không tìm thấy home", nil); return; }
  // iOS dùng lat/lon của chính home (đã set lúc create/update); lon/lat truyền vào không dùng.
  [home getHomeWeatherSketchWithSuccess:^(ThingSmartWeatherSketchModel *m) {
    resolve(@{
      @"condition": m.condition ?: @"",
      @"temp": [NSString stringWithFormat:@"%@", m.temp ?: @""],
      @"iconUrl": m.iconUrl ?: @"",
      @"inIconUrl": m.inIconUrl ?: @"",
    });
  } failure:^(NSError *e) { reject(@"weather_sketch_error", e.localizedDescription, e); }];
}

// limit = số CHỈ SỐ thời tiết tối đa (nhiệt độ/độ ẩm/UV/AQI...) - KHÔNG phải số ngày; 0 (= không set) → SDK
// trả tất cả (theo header ThingSmartWeatherOptionModel).
// unitJson {"tempUnit","pressureUnit","windspeedUnit"} (số nguyên, cùng mã với Android); key thiếu = 0 (unknown)
// → SDK giữ đơn vị của lần gọi thành công trước. Dùng lat/lon của chính home. Trả JSON mảng - key giống
// Android DashBoardBean (objId → id).
- (void)getHomeWeatherDetail:(double)homeId
                       limit:(double)limit
                    unitJson:(NSString *)unitJson
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [self homeOf:homeId];
  if (!home) { TuyaRejectWithDomain(reject, @"no_home", @"Home not found.", @"sdk"); return; }

  NSDictionary *units = @{};
  if ([unitJson stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0) {
    NSData *data = [unitJson dataUsingEncoding:NSUTF8StringEncoding];
    id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![parsed isKindOfClass:[NSDictionary class]]) {
      TuyaRejectWithDomain(reject, @"invalid_param",
                           @"unitJson must be a JSON object {tempUnit, pressureUnit, windspeedUnit}", @"sdk");
      return;
    }
    units = parsed;
  }
  NSUInteger unitValues[3] = {0, 0, 0};
  NSArray<NSString *> *unitKeys = @[ @"tempUnit", @"pressureUnit", @"windspeedUnit" ];
  for (NSUInteger i = 0; i < unitKeys.count; i++) {
    id v = units[unitKeys[i]];
    if (!v || v == [NSNull null]) continue;
    if (![v isKindOfClass:[NSNumber class]] || [v integerValue] < 0) {
      TuyaRejectWithDomain(reject, @"invalid_param",
                           [NSString stringWithFormat:@"unitJson.%@ must be a non-negative integer", unitKeys[i]],
                           @"sdk");
      return;
    }
    unitValues[i] = (NSUInteger)[v integerValue];
  }

  ThingSmartWeatherOptionModel *option = [[ThingSmartWeatherOptionModel alloc] init];
  option.limit = (NSInteger)limit;
  option.temperatureUnit = (ThingSmartWeatherOptionTemperatureUnit)unitValues[0];
  option.pressureUnit = (ThingSmartWeatherOptionPressureUnit)unitValues[1];
  option.windspeedUnit = (ThingSmartWeatherOptionWindSpeedUnit)unitValues[2];

  [home getHomeWeatherDetailWithOption:option success:^(NSArray<ThingSmartWeatherModel *> *list) {
    NSMutableArray *out = [NSMutableArray array];
    for (ThingSmartWeatherModel *w in list) {
      [out addObject:@{
        @"id": @(w.objId),
        @"name": w.name ?: @"",
        @"value": w.value ?: @"",
        @"unit": w.unit ?: @"",
        @"icon": w.icon ?: @"",
        @"fieldName": w.fieldName ?: @"",
        @"metaValue": w.metaValue ?: @"",
        @"roomName": w.roomName ?: @"",
        @"show": @(w.show),
      }];
    }
    NSData *json = [NSJSONSerialization isValidJSONObject:out]
                       ? [NSJSONSerialization dataWithJSONObject:out options:0 error:nil]
                       : nil;
    resolve(json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"[]");
  } failure:^(NSError *e) {
    TuyaRejectNSError(reject, e, @"weather_detail_error", @"Failed to load home weather detail.");
  }];
}

// ---------- Listeners ----------
- (void)startHomeChangeListener:(RCTPromiseResolveBlock)resolve
                         reject:(RCTPromiseRejectBlock)reject {
  self.homeManager.delegate = self;
  resolve(nil);
}

- (void)stopHomeChangeListener:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject {
  _homeManager.delegate = nil;
  resolve(nil);
}

- (void)startHomeStatusListener:(double)homeId
                        resolve:(RCTPromiseResolveBlock)resolve
                         reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [self homeOf:homeId];
  if (!home) { reject(@"no_home", @"Không tìm thấy home", nil); return; }
  home.delegate = self;
  self.homes[@(homeId)] = home;
  resolve(nil);
}

- (void)stopHomeStatusListener:(double)homeId
                       resolve:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = self.homes[@(homeId)];
  home.delegate = nil;
  [self.homes removeObjectForKey:@(homeId)];
  resolve(nil);
}

// ---------- ThingSmartHomeManagerDelegate (cấp manager) ----------
- (void)homeManager:(ThingSmartHomeManager *)manager didAddHome:(ThingSmartHomeModel *)home {
  [self emit:@"onHomeChange" body:@{ @"type": @"homeAdded", @"homeId": @(home.homeId) }];
}

- (void)homeManager:(ThingSmartHomeManager *)manager didRemoveHome:(long long)homeId {
  [self emit:@"onHomeChange" body:@{ @"type": @"homeRemoved", @"homeId": @(homeId) }];
}

- (void)homeManagerDidUpdateInfo:(ThingSmartHomeManager *)manager {
  [self emit:@"onHomeChange" body:@{ @"type": @"homeInfoChanged" }];
}

- (void)homeManager:(ThingSmartHomeManager *)manager didShareDeviceList:(NSArray<ThingSmartDeviceModel *> *)deviceList {
  NSMutableArray *ids = [NSMutableArray array];
  for (ThingSmartDeviceModel *d in deviceList) { [ids addObject:d.devId ?: @""]; }
  [self emit:@"onHomeChange" body:@{ @"type": @"sharedDeviceList", @"devIds": ids }];
}

// ---------- ThingSmartHomeDelegate (cấp home - ⚠️ tên method cần verify) ----------
- (void)home:(ThingSmartHome *)home didAddDeivce:(ThingSmartDeviceModel *)device {
  [self emit:@"onHomeChange" body:@{ @"type": @"deviceAdded",
                                     @"homeId": @(home.homeModel.homeId),
                                     @"devId": device.devId ?: @"" }];
}

- (void)home:(ThingSmartHome *)home didRemoveDeivce:(NSString *)devId {
  [self emit:@"onHomeChange" body:@{ @"type": @"deviceRemoved",
                                     @"homeId": @(home.homeModel.homeId),
                                     @"devId": devId ?: @"" }];
}

- (void)homeDidUpdateInfo:(ThingSmartHome *)home {
  [self emit:@"onHomeChange" body:@{ @"type": @"homeInfoChanged",
                                     @"homeId": @(home.homeModel.homeId) }];
}

- (void)dealloc {
  _homeManager.delegate = nil;
  for (ThingSmartHome *home in _homes.allValues) { home.delegate = nil; }
}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) - không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaHomeSpecJSI>(params);
}

@end
