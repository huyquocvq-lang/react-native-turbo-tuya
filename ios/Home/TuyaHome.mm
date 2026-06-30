#import "TuyaHome.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaHome (iOS) — WIRED: home CRUD (create/list/detail/update/dismiss) + weather sketch + change/status
// listeners (ThingSmartHomeManagerDelegate / ThingSmartHomeDelegate → emit onHomeChange).
// Verbatim selectors: docs/research/tuya-home-sdk-home-management.md (section A iOS).
// TODO: getHomeWeatherDetail (DashBoard/option model field chưa verbatim).
// ⚠️ Verify: ThingSmartHomeModel.role numeric (iOS ThingHomeRoleType có thể KHÁC scheme 2/1/0 của Android — chuẩn hoá sau);
//    tên delegate method cấp home (home:didAddDeivce: / didRemoveDeivce: / homeDidUpdateInfo:) — note đánh dấu cần verify.

static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-home-management.md.", what],
         nil);
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

- (void)getHomeWeatherDetail:(double)homeId
                       limit:(double)limit
                    unitJson:(NSString *)unitJson
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject {
  // intended: [home getHomeWeatherDetailWithOption:(ThingSmartWeatherOptionModel*) success:^(NSArray<ThingSmartWeatherModel*>*) ...]
  //           ThingSmartWeatherModel field chưa verbatim → serialize TODO.
  TuyaTODO(@"getHomeWeatherDetail", reject);
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

// ---------- ThingSmartHomeDelegate (cấp home — ⚠️ tên method cần verify) ----------
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

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter) — không khai lại.

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaHomeSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaHome"; }

@end
