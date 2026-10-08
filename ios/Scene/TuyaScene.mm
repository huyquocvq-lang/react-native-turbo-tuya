#import "TuyaScene.h"
#import "TuyaReject.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>
#import <YYModel/YYModel.h>

// TuyaScene (iOS) - WIRED: list/detail/save/modify/delete/execute/enable/disable + build* + device/city lists.
// Selector VERBATIM từ header SDK thật: Pods/ThingSmartSceneCoreKit/.../Headers (ThingSmartScene.h, ThingSmartSceneManager.h,
// ThingSmartSceneConditionFactory/ExprBuilder.h, ThingSmartSceneActionFactory.h, TSceneRequestInfo.h).
//   save   → +[ThingSmartScene addScene:homeID:] (bản thay thế của API deprecated; tự bật theo dõi geofence)
//   modify → getSceneDetail → sửa model → -[ThingSmartScene editScene:] (giữ enabled/displayColor/statusConditions...)
//   SDK KHÔNG gửi ruleGenre: -isManual (ruleGenre==1, hoặc không có condition) quyết định tap-to-run và bỏ `conditions`.
//   Khi lưu, SDK chỉ serialize: condition {id, condType(=2 khi simple), entityType, entityId, entitySubIds, expr, extraInfo,
//   iconUrl, devDelMark}; action {id, actionExecutor, executorProperty, entityId, extraProperty, devDelMark, relationGroup}.
//   (entityName/exprDisplay chỉ để hiển thị - server tự sinh lại.)
//
// HỢP ĐỒNG JSON (build* ↔ save/modify ↔ getSceneDetail): mỗi phần tử = -yy_modelToJSONObject của chính model SDK
// (ThingSmartSceneConditionModel / ActionModel / PreConditionModel - SDK parse response cloud bằng YYModel + mapper riêng,
// vd conditionId ↔ "id") → đọc lại bằng +yy_modelWithJSON:. conditionsJson/actionsJson/preConditionsJson = JSON array;
// phần tử là object HOẶC chính chuỗi build* trả về. Chuỗi Android (fastjson) KHÁC iOS - không trộn giữa 2 nền tảng.
//
// Giá trị DP (op/value): kiểu theo schema cache của thiết bị (bool/value/enum/string/raw); chưa có schema (home chưa load)
// thì đoán: "true"/"false" → bool, số nguyên → value, còn lại → enum. Value = số nguyên THÔ (chưa chia scale).
//
// Event onSceneChange: iOS chỉ có ThingSmartSceneManagerDelegate (state "enable"/"disable") - add/update/delete không có
// listener → JS tự refresh list.

static NSString * const kTuyaSceneEvent = @"onSceneChange";

// ---------- Reject (shape { code, message, domain } - src/errors.ts) ----------
// Mã lỗi Tuya THẬT = NSError.code; SDK không trả NSError thì dùng fallback và nói rõ.
static void TuyaSceneRejectError(RCTPromiseRejectBlock reject, NSError *error, NSString *fallbackCode) {
  if (error) {
    TuyaRejectWithDomain(reject, [@(error.code) stringValue], error.localizedDescription ?: fallbackCode, @"sdk");
  } else {
    TuyaRejectWithDomain(reject, fallbackCode, @"Tuya SDK returned no error detail.", @"sdk");
  }
}

static void TuyaSceneInvalid(RCTPromiseRejectBlock reject, NSString *message) {
  TuyaRejectWithDomain(reject, @"invalid_param", message, @"sdk");
}

// ThingSmartScene không có init theo sceneId (đã verify header ThingSmartSceneCoreKit) - chỉ nhận
// ThingSmartSceneModel, nên dựng model tối thiểu chỉ có sceneId. Call site phải giữ scene sống tới khi
// callback về (capture vào block) vì instance sở hữu request đang bay (SDK có cancelRequest).
static ThingSmartScene *TuyaSceneById(NSString *sceneId) {
  ThingSmartSceneModel *model = [[ThingSmartSceneModel alloc] init];
  model.sceneId = sceneId;
  return [ThingSmartScene sceneWithSceneModel:model];
}

// ---------- JSON ----------
static NSString *TuyaSceneJsonString(id obj, NSString *fallback) {
  if (!obj || ![NSJSONSerialization isValidJSONObject:obj]) return fallback;
  NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : fallback;
}

static id TuyaSceneJsonParse(NSString *json) {
  if (![json isKindOfClass:[NSString class]]) return nil;
  NSData *d = [json dataUsingEncoding:NSUTF8StringEncoding];
  return d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
}

static NSString *TuyaSceneModelJson(id model) {
  return TuyaSceneJsonString([model yy_modelToJSONObject], @"{}");
}

static NSString *TuyaSceneModelsJson(NSArray *models) {
  NSMutableArray *out = [NSMutableArray array];
  for (id m in models ?: @[]) {
    id obj = [m yy_modelToJSONObject];
    if (obj) [out addObject:obj];
  }
  return TuyaSceneJsonString(out, @"[]");
}

/** JSON array (chuỗi hoặc array thật) → model; phần tử là object hoặc chuỗi JSON do build* trả về. */
static NSArray *TuyaSceneModelList(id raw, Class cls, NSString *field, NSString **error) {
  NSArray *arr = nil;
  if (raw == nil || raw == (id)[NSNull null]) {
    arr = @[];
  } else if ([raw isKindOfClass:[NSArray class]]) {
    arr = raw;
  } else if ([raw isKindOfClass:[NSString class]]) {
    NSString *s = [(NSString *)raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    id parsed = s.length ? TuyaSceneJsonParse(s) : @[];
    if ([parsed isKindOfClass:[NSArray class]]) arr = parsed;
  }
  if (!arr) {
    *error = [NSString stringWithFormat:@"%@ must be a JSON array string", field];
    return nil;
  }
  NSMutableArray *models = [NSMutableArray arrayWithCapacity:arr.count];
  for (NSUInteger i = 0; i < arr.count; i++) {
    id e = arr[i];
    id m = ([e isKindOfClass:[NSDictionary class]] || [e isKindOfClass:[NSString class]]) ? [cls yy_modelWithJSON:e] : nil;
    if (!m) {
      *error = [NSString stringWithFormat:@"%@[%lu] is not a valid object", field, (unsigned long)i];
      return nil;
    }
    [models addObject:m];
  }
  return models;
}

// ---------- Mapping kết quả ----------
/** ruleGenre thiếu (0) → suy ra như SDK (-isManual: không có condition = tap-to-run). */
static NSInteger TuyaSceneGenre(ThingSmartSceneModel *m) {
  if (m.ruleGenre == ThingSmartSceneRuleGenreManual) return 1;
  if (m.ruleGenre == ThingSmartSceneRuleGenreAuto) return 2;
  return [m isManual] ? 1 : 2;
}

static NSInteger TuyaSceneMatchType(ThingSmartSceneModel *m) {
  return m.matchType == ThingSmartConditionMatchAll ? 2 : 1;
}

static NSDictionary *TuyaSceneSaved(ThingSmartSceneModel *scene, NSString *fallbackId, NSString *fallbackName,
                                    NSInteger fallbackGenre) {
  NSInteger genre = (scene.ruleGenre == ThingSmartSceneRuleGenreManual || scene.ruleGenre == ThingSmartSceneRuleGenreAuto)
                        ? (NSInteger)scene.ruleGenre
                        : fallbackGenre;
  return @{
    @"sceneId": scene.sceneId.length ? scene.sceneId : (fallbackId ?: @""),
    @"name": scene.name.length ? scene.name : (fallbackName ?: @""),
    @"ruleGenre": @(genre),
  };
}

static NSArray *TuyaSceneDeviceItems(NSArray *list) {
  NSMutableArray *out = [NSMutableArray array];
  for (id d in list ?: @[]) {
    if (![d isKindOfClass:[ThingSmartDeviceModel class]]) continue;
    ThingSmartDeviceModel *m = d;
    [out addObject:@{ @"devId": m.devId ?: @"", @"name": m.name ?: @"" }];
  }
  return out;
}

static NSDictionary *TuyaSceneCity(ThingSmartCityModel *c) {
  return @{ @"cityId": [@(c.cityId) stringValue], @"cityName": c.city ?: @"" };
}

// ---------- paramsJson (save/modify) ----------
/** Parse + validate. Key vắng mặt = không có trong dict → modify giữ nguyên giá trị cũ. */
static NSDictionary *TuyaSceneParseParams(NSString *paramsJson, NSString **error) {
  id root = TuyaSceneJsonParse(paramsJson);
  if (![root isKindOfClass:[NSDictionary class]]) {
    *error = @"paramsJson must be a JSON object";
    return nil;
  }
  NSDictionary *j = root;
  NSMutableDictionary *p = [NSMutableDictionary dictionary];
  if ([j[@"name"] isKindOfClass:[NSString class]]) p[@"name"] = j[@"name"];
  if ([j[@"background"] isKindOfClass:[NSString class]]) p[@"background"] = j[@"background"];
  for (NSString *key in @[ @"ruleGenre", @"matchType" ]) {
    id v = j[key];
    if (!v || v == (id)[NSNull null]) continue;
    NSInteger n = [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
    if (n != 1 && n != 2) {
      *error = [key isEqualToString:@"ruleGenre"] ? @"ruleGenre must be 1 (tap-to-run) or 2 (automation)"
                                                  : @"matchType must be 1 (any) or 2 (all)";
      return nil;
    }
    p[key] = @(n);
  }
  NSDictionary *lists = @{
    @"conditionsJson": @[ @"conditions", [ThingSmartSceneConditionModel class] ],
    @"actionsJson": @[ @"actions", [ThingSmartSceneActionModel class] ],
    @"preConditionsJson": @[ @"preConditions", [ThingSmartScenePreConditionModel class] ],
  };
  for (NSString *field in lists) {
    if (!j[field]) continue;
    NSArray *spec = lists[field];
    NSArray *models = TuyaSceneModelList(j[field], spec[1], field, error);
    if (!models) return nil;
    p[spec[0]] = models;
  }
  return p;
}

/** Gán các field có mặt; tap-to-run không mang condition (SDK cũng tự bỏ khi -isManual). */
static void TuyaSceneApplyParams(ThingSmartSceneModel *m, NSDictionary *p) {
  if (p[@"name"]) m.name = p[@"name"];
  if (p[@"ruleGenre"]) {
    m.ruleGenre = [p[@"ruleGenre"] integerValue] == 1 ? ThingSmartSceneRuleGenreManual : ThingSmartSceneRuleGenreAuto;
  }
  if (p[@"matchType"]) {
    m.matchType = [p[@"matchType"] integerValue] == 2 ? ThingSmartConditionMatchAll : ThingSmartConditionMatchAny;
  }
  NSString *background = p[@"background"];
  if (background.length) m.background = background;
  if (p[@"conditions"]) m.conditions = p[@"conditions"];
  if (p[@"actions"]) m.actions = p[@"actions"];
  if (p[@"preConditions"]) m.preConditions = p[@"preConditions"];
  if (m.ruleGenre == ThingSmartSceneRuleGenreManual) m.conditions = @[];
}

static NSString *TuyaSceneValidate(ThingSmartSceneModel *m) {
  if (m.name.length == 0) return @"name is required";
  if (m.actions.count == 0) return @"actionsJson needs at least 1 action";
  if (m.ruleGenre == ThingSmartSceneRuleGenreAuto && m.conditions.count == 0) {
    return @"automation (ruleGenre 2) needs at least 1 condition";
  }
  return nil;
}

// ---------- Giá trị DP ----------
static NSString *TuyaSceneTrim(NSString *s) {
  return [s ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL TuyaSceneMatches(NSString *s, NSString *pattern) {
  return [[NSPredicate predicateWithFormat:@"SELF MATCHES %@", pattern] evaluateWithObject:s ?: @""];
}

static ThingSmartDeviceModel *TuyaSceneDevice(NSString *devId) {
  return [ThingSmartDevice deviceWithDeviceId:devId].deviceModel;
}

/** Kiểu DP theo schema cache: bool/value/enum/string/raw/bitmap; nil khi chưa có schema. */
static NSString *TuyaSceneDpType(ThingSmartDeviceModel *device, NSString *dpId) {
  for (ThingSmartSchemaModel *s in device.schemaArray ?: @[]) {
    if (![[NSString stringWithFormat:@"%@", s.dpId] isEqualToString:dpId]) continue;
    if ([s.type.lowercaseString isEqualToString:@"raw"]) return @"raw";
    NSString *t = s.property.type.lowercaseString;
    return t.length ? t : nil;
  }
  return nil;
}

static NSString *TuyaSceneSniffType(NSString *value) {
  NSString *v = TuyaSceneTrim(value).lowercaseString;
  if ([v isEqualToString:@"true"] || [v isEqualToString:@"false"]) return @"bool";
  if (TuyaSceneMatches(v, @"-?[0-9]+")) return @"value";
  return @"enum";
}

static NSNumber *TuyaSceneBool(NSString *value) {
  NSString *v = TuyaSceneTrim(value).lowercaseString;
  if ([v isEqualToString:@"true"] || [v isEqualToString:@"1"]) return @YES;
  if ([v isEqualToString:@"false"] || [v isEqualToString:@"0"]) return @NO;
  return nil;
}

/** Số nguyên 32-bit (DP value của Tuya); nil khi không phải số nguyên. */
static NSNumber *TuyaSceneInt(NSString *value) {
  NSString *v = TuyaSceneTrim(value);
  if (!TuyaSceneMatches(v, @"-?[0-9]{1,10}")) return nil;
  long long n = v.longLongValue;
  if (n < INT32_MIN || n > INT32_MAX) return nil;
  return @((NSInteger)n);
}

static NSString *TuyaSceneOp(NSString *op) {
  NSString *o = TuyaSceneTrim(op);
  return o.length ? o : @"==";
}

static BOOL TuyaSceneIsValueOp(NSString *op) {
  return [@[ @"==", @"<", @">", @"<=", @">=" ] containsObject:op];
}

@interface TuyaScene () <ThingSmartSceneManagerDelegate>
@end

@implementation TuyaScene

RCT_EXPORT_MODULE()

- (NSArray<NSString *> *)supportedEvents { return @[kTuyaSceneEvent]; }

// ---------- List / detail ----------
- (void)getSceneList:(double)homeId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartSceneManager sharedInstance] getSceneListWithHomeId:(long long)homeId
                                                          success:^(NSArray<ThingSmartSceneModel *> *list) {
    NSMutableArray *out = [NSMutableArray array];
    for (ThingSmartSceneModel *m in list) {
      [out addObject:@{
        @"sceneId": m.sceneId ?: @"",
        @"name": m.name ?: @"",
        @"ruleGenre": @(TuyaSceneGenre(m)),
        @"enabled": @(m.enabled),
        @"matchType": @(TuyaSceneMatchType(m)),
        @"displayColor": m.displayColor ?: @"",
        @"coverIcon": m.coverIcon ?: @"",
      }];
    }
    resolve(out);
  } failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"scene_list_error"); }];
}

- (void)getSceneDetail:(double)homeId
               sceneId:(NSString *)sceneId
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  if (sceneId.length == 0) { TuyaSceneInvalid(reject, @"sceneId is required"); return; }
  [[ThingSmartSceneManager sharedInstance] getSceneDetailWithHomeId:(long long)homeId
                                                            sceneId:sceneId
                                                            success:^(ThingSmartSceneModel *m) {
    if (!m) {
      TuyaRejectWithDomain(reject, @"scene_not_found", [NSString stringWithFormat:@"Scene %@ not found", sceneId], @"sdk");
      return;
    }
    resolve(@{
      @"sceneId": m.sceneId.length ? m.sceneId : sceneId,
      @"name": m.name ?: @"",
      @"ruleGenre": @(TuyaSceneGenre(m)),
      @"enabled": @(m.enabled),
      @"matchType": @(TuyaSceneMatchType(m)),
      @"conditionsJson": TuyaSceneModelsJson(m.conditions),
      @"actionsJson": TuyaSceneModelsJson(m.actions),
      @"preConditionsJson": TuyaSceneModelsJson(m.preConditions),
    });
  } failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"scene_detail_error"); }];
}

// ---------- Create / modify / delete ----------
- (void)saveScene:(double)homeId
       paramsJson:(NSString *)paramsJson
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject {
  NSString *error = nil;
  NSDictionary *p = TuyaSceneParseParams(paramsJson, &error);
  if (!p) { TuyaSceneInvalid(reject, error); return; }
  NSInteger genre = p[@"ruleGenre"] ? [p[@"ruleGenre"] integerValue] : ([p[@"conditions"] count] ? 2 : 1);
  ThingSmartSceneModel *model = [[ThingSmartSceneModel alloc] init];
  model.ruleGenre = genre == 1 ? ThingSmartSceneRuleGenreManual : ThingSmartSceneRuleGenreAuto;
  model.matchType = ThingSmartConditionMatchAny;
  model.enabled = YES; // SDK gửi enabled của model cho automation → phải bật sẵn
  model.stickyOnTop = YES; // = mặc định NormalScene() bên Android (hiện ở trang chủ)
  model.conditions = @[];
  model.preConditions = @[];
  TuyaSceneApplyParams(model, p);
  NSString *invalid = TuyaSceneValidate(model);
  if (invalid) { TuyaSceneInvalid(reject, invalid); return; }

  TSceneRequestInfo *info = [[TSceneRequestInfo alloc] init];
  info.sceneModel = model;
  info.gid = (long long)homeId;
  info.needCleanGidSid = NO;
  [ThingSmartScene addScene:info
                     homeID:(long long)homeId
                    success:^(ThingSmartSceneModel *scene) { resolve(TuyaSceneSaved(scene, @"", model.name, genre)); }
                    failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"save_scene_error"); }];
}

// Sửa trên bản chi tiết mới nhất (giữ enabled/displayColor/statusConditions...), chỉ đè key có trong paramsJson.
- (void)modifyScene:(double)homeId
            sceneId:(NSString *)sceneId
         paramsJson:(NSString *)paramsJson
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject {
  if (sceneId.length == 0) { TuyaSceneInvalid(reject, @"sceneId is required"); return; }
  NSString *error = nil;
  NSDictionary *p = TuyaSceneParseParams(paramsJson, &error);
  if (!p) { TuyaSceneInvalid(reject, error); return; }
  long long hid = (long long)homeId;
  [[ThingSmartSceneManager sharedInstance] getSceneDetailWithHomeId:hid
                                                            sceneId:sceneId
                                                            success:^(ThingSmartSceneModel *model) {
    if (!model) {
      TuyaRejectWithDomain(reject, @"scene_not_found", [NSString stringWithFormat:@"Scene %@ not found", sceneId], @"sdk");
      return;
    }
    if (model.sceneId.length == 0) model.sceneId = sceneId;
    TuyaSceneApplyParams(model, p);
    NSString *invalid = TuyaSceneValidate(model);
    if (invalid) { TuyaSceneInvalid(reject, invalid); return; }

    TSceneRequestInfo *info = [[TSceneRequestInfo alloc] init];
    info.sceneModel = model;
    info.gid = hid;
    info.needCleanGidSid = NO;
    NSInteger genre = TuyaSceneGenre(model);
    ThingSmartScene *scene = [ThingSmartScene sceneWithSceneModel:model];
    [scene editScene:info
             success:^(ThingSmartSceneModel *saved) {
      (void)scene;
      resolve(TuyaSceneSaved(saved, sceneId, model.name, genre));
    }
             failure:^(NSError *e) {
      (void)scene;
      TuyaSceneRejectError(reject, e, @"modify_scene_error");
    }];
  } failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"modify_scene_error"); }];
}

- (void)deleteScene:(double)homeId
            sceneId:(NSString *)sceneId
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject {
  ThingSmartScene *scene = TuyaSceneById(sceneId);
  [scene deleteSceneWithHomeId:(long long)homeId
                       success:^(BOOL result) { (void)scene; resolve(@(result)); }
                       failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"delete_scene_error"); }];
}

// ---------- Execute / automation ----------
- (void)executeScene:(double)homeId
             sceneId:(NSString *)sceneId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  ThingSmartScene *scene = TuyaSceneById(sceneId);
  [scene executeSceneWithSuccess:^{ (void)scene; resolve(nil); }
                         failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"execute_scene_error"); }];
}

- (void)enableAutomation:(NSString *)sceneId
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  ThingSmartScene *scene = TuyaSceneById(sceneId);
  [scene enableSceneWithSuccess:^{ (void)scene; resolve(@YES); }
                        failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"enable_scene_error"); }];
}

- (void)disableAutomation:(NSString *)sceneId
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  ThingSmartScene *scene = TuyaSceneById(sceneId);
  [scene disableSceneWithSuccess:^{ (void)scene; resolve(@YES); }
                         failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"disable_scene_error"); }];
}

// Android-only theo spec: ThingSmartSceneCoreKit (iOS) không có API bật automation theo thời lượng (đã grep header).
- (void)enableAutomationWithTime:(NSString *)sceneId
                       durationMs:(double)durationMs
                          resolve:(RCTPromiseResolveBlock)resolve
                           reject:(RCTPromiseRejectBlock)reject {
  TuyaRejectWithDomain(reject, @"ios_todo", // cùng mã với các stub iOS khác → JS fallback một chỗ
                       @"enableAutomationWithTime is Android-only: the iOS Tuya SDK (ThingSmartSceneCoreKit) has no API "
                       @"to enable an automation for a duration. Use enableAutomation instead.",
                       @"sdk");
}

// ---------- Builders (condition/action → JSON) ----------
- (void)buildDeviceCondition:(NSString *)devId
                        dpId:(NSString *)dpId
                          op:(NSString *)op
                       value:(NSString *)value
                     resolve:(RCTPromiseResolveBlock)resolve
                      reject:(RCTPromiseRejectBlock)reject {
  if (devId.length == 0 || dpId.length == 0) { TuyaSceneInvalid(reject, @"devId and dpId are required"); return; }
  ThingSmartDeviceModel *device = TuyaSceneDevice(devId);
  NSString *type = TuyaSceneDpType(device, dpId) ?: TuyaSceneSniffType(value);
  NSString *operator_ = TuyaSceneOp(op);
  ThingSmartSceneExprModel *expr = nil;
  BOOL simpleMatch = NO;
  if ([type isEqualToString:@"bool"]) {
    NSNumber *b = TuyaSceneBool(value);
    if (![operator_ isEqualToString:@"=="]) { TuyaSceneInvalid(reject, @"bool DP only supports op '=='"); return; }
    if (!b) { TuyaSceneInvalid(reject, [NSString stringWithFormat:@"invalid bool value '%@'", value]); return; }
    expr = [ThingSmartSceneConditionExprBuilder createBoolExprWithType:dpId isTrue:b.boolValue exprType:kExprTypeDevice];
  } else if ([type isEqualToString:@"value"]) {
    NSNumber *n = TuyaSceneInt(value);
    if (!TuyaSceneIsValueOp(operator_)) { TuyaSceneInvalid(reject, @"op must be one of ==, <, >, <=, >="); return; }
    if (!n) { TuyaSceneInvalid(reject, @"value must be an integer (raw DP value, before scale)"); return; }
    expr = [ThingSmartSceneConditionExprBuilder createValueExprWithType:dpId
                                                               operater:operator_
                                                            chooseValue:n.integerValue
                                                               exprType:kExprTypeDevice];
  } else if ([type isEqualToString:@"enum"]) {
    if (![operator_ isEqualToString:@"=="]) { TuyaSceneInvalid(reject, @"enum DP only supports op '=='"); return; }
    if (TuyaSceneTrim(value).length == 0) { TuyaSceneInvalid(reject, @"value is required"); return; }
    expr = [ThingSmartSceneConditionExprBuilder createEnumExprWithType:dpId
                                                           chooseValue:TuyaSceneTrim(value)
                                                              exprType:kExprTypeDevice];
  } else if ([type isEqualToString:@"string"] || [type isEqualToString:@"raw"]) {
    // string/raw: biểu thức ["$dpX"] (báo bất kỳ giá trị) + condType simple; value bỏ qua.
    simpleMatch = YES;
    expr = [ThingSmartSceneConditionExprBuilder createRawExprWithType:dpId exprType:kExprTypeDevice];
  } else {
    TuyaSceneInvalid(reject, [NSString stringWithFormat:@"DP %@ of type '%@' is not supported as a condition", dpId, type]);
    return;
  }
  // Dựng tay giống -createDeviceConditionWithDevice:dpModel:exprModel: (factory cần ThingSmartSceneDPModel từ API DP list).
  ThingSmartSceneConditionModel *c = [[ThingSmartSceneConditionModel alloc] init];
  c.entityType = AutoTypeDevice;
  c.entityId = devId;
  c.entitySubIds = dpId;
  c.entityName = device.name;
  c.iconUrl = device.iconUrl;
  c.expr = expr.expr ? @[ expr.expr ] : @[];
  c.conditionExpressionType = simpleMatch ? ThingSConditionExpressionTypeSimple : ThingSConditionExpressionTypePrecise;
  resolve(TuyaSceneModelJson(c));
}

// weatherType: temp · humidity · condition · pm25 · aqi · sunsetrise · windSpeed (giống WeatherType Android).
// temp/windSpeed là số (°C, m/s) → op so sánh; còn lại là enum (vd condition 'sunny') → op '=='.
- (void)buildWeatherCondition:(NSString *)cityId
                     cityName:(NSString *)cityName
                  weatherType:(NSString *)weatherType
                           op:(NSString *)op
                        value:(NSString *)value
                      resolve:(RCTPromiseResolveBlock)resolve
                       reject:(RCTPromiseRejectBlock)reject {
  if (cityId.length == 0) { TuyaSceneInvalid(reject, @"cityId is required"); return; }
  NSString *wt = TuyaSceneTrim(weatherType);
  BOOL isValueType = [@[ @"temp", @"windSpeed" ] containsObject:wt];
  BOOL isEnumType = [@[ @"humidity", @"condition", @"pm25", @"aqi", @"sunsetrise" ] containsObject:wt];
  if (!isValueType && !isEnumType) {
    TuyaSceneInvalid(reject, [NSString stringWithFormat:@"unsupported weatherType '%@'", weatherType]);
    return;
  }
  NSString *operator_ = TuyaSceneOp(op);
  ThingSmartSceneExprModel *expr = nil;
  if (isValueType) {
    NSNumber *n = TuyaSceneInt(value);
    if (!TuyaSceneIsValueOp(operator_)) { TuyaSceneInvalid(reject, @"op must be one of ==, <, >, <=, >="); return; }
    if (!n) { TuyaSceneInvalid(reject, @"value must be an integer"); return; }
    expr = [ThingSmartSceneConditionExprBuilder createValueExprWithType:wt
                                                               operater:operator_
                                                            chooseValue:n.integerValue
                                                               exprType:kExprTypeWhether];
  } else {
    if (![operator_ isEqualToString:@"=="]) { TuyaSceneInvalid(reject, @"enum weather types only support op '=='"); return; }
    if (TuyaSceneTrim(value).length == 0) { TuyaSceneInvalid(reject, @"value is required"); return; }
    expr = [ThingSmartSceneConditionExprBuilder createEnumExprWithType:wt
                                                           chooseValue:TuyaSceneTrim(value)
                                                              exprType:kExprTypeWhether];
  }
  // extraInfo giống TSmartSceneConditionExtraInfoBuilder (cityName + đơn vị) và WeatherConditionBuilder Android.
  NSMutableDictionary *extra = [NSMutableDictionary dictionary];
  if (cityName.length) extra[@"cityName"] = cityName;
  if ([wt isEqualToString:@"temp"]) extra[@"tempUnit"] = @"celsius";
  if ([wt isEqualToString:@"windSpeed"]) extra[@"windSpeedUnit"] = @"m/s";

  ThingSmartSceneConditionModel *c = [[ThingSmartSceneConditionModel alloc] init];
  c.entityType = AutoTypeWhether;
  c.entityId = cityId;
  c.entityName = cityName;
  c.cityName = cityName;
  c.entitySubIds = wt;
  c.expr = expr.expr ? @[ expr.expr ] : @[];
  c.extraInfo = extra;
  c.conditionExpressionType = ThingSConditionExpressionTypePrecise;
  resolve(TuyaSceneModelJson(c));
}

// loops: 7 ký tự CN→T7 ('0000000' = một lần, cần date). time 'HH:mm'. date 'yyyyMMdd' (rỗng = hôm nay theo timeZoneId).
- (void)buildTimerCondition:(NSString *)timeZoneId
                      loops:(NSString *)loops
                       time:(NSString *)time
                       date:(NSString *)date
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject {
  NSString *tzId = TuyaSceneTrim(timeZoneId);
  NSTimeZone *tz = tzId.length ? [NSTimeZone timeZoneWithName:tzId] : [NSTimeZone localTimeZone];
  if (!tz) { TuyaSceneInvalid(reject, [NSString stringWithFormat:@"unknown timeZoneId '%@'", timeZoneId]); return; }
  if (!TuyaSceneMatches(loops, @"[01]{7}")) { TuyaSceneInvalid(reject, @"loops must be 7 chars of 0/1 (Sunday→Saturday)"); return; }
  if (!TuyaSceneMatches(time, @"([01][0-9]|2[0-3]):[0-5][0-9]")) { TuyaSceneInvalid(reject, @"time must be HH:mm"); return; }
  NSString *day = TuyaSceneTrim(date);
  if (day.length == 0) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.timeZone = tz;
    f.dateFormat = @"yyyyMMdd";
    day = [f stringFromDate:[NSDate date]];
  }
  if (!TuyaSceneMatches(day, @"[0-9]{8}")) { TuyaSceneInvalid(reject, @"date must be yyyyMMdd"); return; }
  ThingSmartSceneExprModel *expr = [ThingSmartSceneConditionExprBuilder createTimerExprWithTimeZoneId:tz.name
                                                                                                loops:loops
                                                                                                 date:day
                                                                                                 time:time];
  ThingSmartSceneConditionModel *c = [ThingSmartSceneConditionFactory createTimerConditionWithExprModel:expr];
  c.exprDisplay = time;
  resolve(TuyaSceneModelJson(c));
}

// Chỉ build condition; +addScene:/-editScene: của SDK tự đăng ký theo dõi geofence (ThingSmartSceneGeoFenceService).
- (void)buildGeofenceCondition:(NSString *)geoType
                      latitude:(double)latitude
                     longitude:(double)longitude
                        radius:(double)radius
                         title:(NSString *)title
                       resolve:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject {
  NSString *g = TuyaSceneTrim(geoType).lowercaseString;
  GeoFenceType type;
  if ([g isEqualToString:@"reach"] || [g isEqualToString:@"enter"]) {
    type = kGeoFenceTypeReach;
  } else if ([g isEqualToString:@"exit"] || [g isEqualToString:@"leave"]) {
    type = kGeoFenceTypeExit;
  } else if ([g isEqualToString:@"inside"]) {
    type = kGeoFenceTypeIn;
  } else if ([g isEqualToString:@"outside"]) {
    type = kGeoFenceTypeOut;
  } else {
    TuyaSceneInvalid(reject, @"geoType must be 'reach' or 'exit'");
    return;
  }
  if (isnan(latitude) || latitude < -90 || latitude > 90 || isnan(longitude) || longitude < -180 || longitude > 180) {
    TuyaSceneInvalid(reject, @"latitude/longitude out of range");
    return;
  }
  if (isnan(radius) || radius < 1) { TuyaSceneInvalid(reject, @"radius must be >= 1 (meters)"); return; }
  ThingSmartSceneConditionModel *c = [ThingSmartSceneConditionFactory createGeoFenceConditionWithGeoType:type
                                                                                                 geoLati:latitude
                                                                                                geoLonti:longitude
                                                                                               geoRadius:radius
                                                                                                geoTitle:title ?: @""];
  if (!c) { TuyaSceneInvalid(reject, @"Tuya SDK rejected the geofence parameters"); return; }
  c.entityName = title;
  resolve(TuyaSceneModelJson(c));
}

- (void)buildDeviceAction:(NSString *)devId
                     dpId:(NSString *)dpId
                    value:(NSString *)value
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  if (devId.length == 0 || dpId.length == 0) { TuyaSceneInvalid(reject, @"devId and dpId are required"); return; }
  ThingSmartDeviceModel *device = TuyaSceneDevice(devId);
  NSString *type = TuyaSceneDpType(device, dpId) ?: TuyaSceneSniffType(value);
  id typed = value ?: @""; // enum/string/raw(hex) gửi nguyên chuỗi
  if ([type isEqualToString:@"bool"]) {
    typed = TuyaSceneBool(value);
    if (!typed) { TuyaSceneInvalid(reject, [NSString stringWithFormat:@"invalid bool value '%@'", value]); return; }
  } else if ([type isEqualToString:@"value"] || [type isEqualToString:@"bitmap"]) {
    typed = TuyaSceneInt(value);
    if (!typed) { TuyaSceneInvalid(reject, @"value must be an integer (raw DP value, before scale)"); return; }
  }
  ThingSmartSceneActionModel *a = [ThingSmartSceneActionFactory createDeviceDpActionWithDevId:devId
                                                                                      devName:device.name ?: @""
                                                                             executerProperty:@{ dpId: typed }
                                                                                extraProperty:@{}];
  if (!a) { TuyaSceneInvalid(reject, @"Tuya SDK rejected the device action parameters"); return; }
  resolve(TuyaSceneModelJson(a));
}

// Factory quy giờ ra phút: executorProperty {"minutes":"h*60+m","seconds":"s"} - giống DelayActionBuilder Android.
- (void)buildDelayAction:(double)hours
                 minutes:(double)minutes
                 seconds:(double)seconds
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  for (NSNumber *n in @[ @(hours), @(minutes), @(seconds) ]) {
    double v = n.doubleValue;
    if (isnan(v) || v < 0 || v != floor(v)) {
      TuyaSceneInvalid(reject, @"hours/minutes/seconds must be non-negative integers");
      return;
    }
  }
  if (hours == 0 && minutes == 0 && seconds == 0) { TuyaSceneInvalid(reject, @"delay must be > 0"); return; }
  ThingSmartSceneActionModel *a =
      [ThingSmartSceneActionFactory createDelayActionWithHours:[@((NSInteger)hours) stringValue]
                                                       minutes:[@((NSInteger)minutes) stringValue]
                                                       seconds:[@((NSInteger)seconds) stringValue]];
  if (!a) { TuyaSceneInvalid(reject, @"Tuya SDK rejected the delay parameters"); return; }
  resolve(TuyaSceneModelJson(a));
}

// Factory trả nil khi sceneName rỗng → dùng sceneId làm tên (entityName chỉ để hiển thị, SDK không gửi lên cloud).
- (void)buildTriggerSceneAction:(NSString *)sceneId
                      sceneName:(NSString *)sceneName
                        resolve:(RCTPromiseResolveBlock)resolve
                         reject:(RCTPromiseRejectBlock)reject {
  if (sceneId.length == 0) { TuyaSceneInvalid(reject, @"sceneId is required"); return; }
  ThingSmartSceneActionModel *a =
      [ThingSmartSceneActionFactory createTriggerSceneActionWithSceneId:sceneId
                                                              sceneName:sceneName.length ? sceneName : sceneId];
  if (!a) { TuyaSceneInvalid(reject, @"Tuya SDK rejected the trigger-scene parameters"); return; }
  resolve(TuyaSceneModelJson(a));
}

- (void)buildAutomationToggleAction:(NSString *)sceneId
                             enable:(BOOL)enable
                            resolve:(RCTPromiseResolveBlock)resolve
                             reject:(RCTPromiseRejectBlock)reject {
  if (sceneId.length == 0) { TuyaSceneInvalid(reject, @"sceneId is required"); return; }
  ThingSmartSceneActionModel *a =
      [ThingSmartSceneActionFactory createSwitchAutoActionWithSceneId:sceneId
                                                            sceneName:sceneId
                                                                 type:enable ? kAutoSwitchTypeEnable : kAutoSwitchTypeDisable];
  if (!a) { TuyaSceneInvalid(reject, @"Tuya SDK rejected the automation toggle parameters"); return; }
  resolve(TuyaSceneModelJson(a));
}

// channel: 'message' (push trung tâm tin nhắn) · 'sms' · 'phone' (gọi thoại - gói dịch vụ trả phí của Tuya).
- (void)buildNotificationAction:(NSString *)channel
                        resolve:(RCTPromiseResolveBlock)resolve
                         reject:(RCTPromiseRejectBlock)reject {
  NSString *ch = TuyaSceneTrim(channel).lowercaseString;
  ThingSmartSceneActionModel *a = nil;
  if ([ch isEqualToString:@"message"]) {
    a = [ThingSmartSceneActionFactory createSendNotificationAction];
  } else if ([ch isEqualToString:@"sms"]) {
    a = [ThingSmartSceneActionFactory createSmsAction];
  } else if ([ch isEqualToString:@"phone"]) {
    a = [ThingSmartSceneActionFactory createCallAction];
  } else {
    TuyaSceneInvalid(reject, @"channel must be 'message', 'sms' or 'phone'");
    return;
  }
  resolve(TuyaSceneModelJson(a));
}

// ---------- Helpers ----------
// Danh sách dựng từ cache thiết bị của SDK → cần nạp home (getHomeDetail) trước, nếu không có thể rỗng.
- (void)getConditionDeviceList:(double)homeId
                       resolve:(RCTPromiseResolveBlock)resolve
                        reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartSceneManager sharedInstance] getConditionDeviceListWithHomeId:(long long)homeId
                                                                    success:^(NSArray<ThingSmartDeviceModel *> *list) {
    resolve(TuyaSceneDeviceItems(list));
  } failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"condition_device_list_error"); }];
}

// Chỉ trả thiết bị lẻ (bỏ groupList): buildDeviceAction phát `dpIssue` cho devId, không hỗ trợ group.
- (void)getActionDeviceList:(double)homeId
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartSceneManager sharedInstance] getActionGroupListAndDeviceListWithHomeId:(long long)homeId
                                                                             success:^(NSDictionary *dict) {
    id list = [dict isKindOfClass:[NSDictionary class]] ? dict[@"deviceList"] : nil;
    resolve(TuyaSceneDeviceItems([list isKindOfClass:[NSArray class]] ? list : @[]));
  } failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"action_device_list_error"); }];
}

- (void)getCityListByCountryCode:(NSString *)countryCode
                         resolve:(RCTPromiseResolveBlock)resolve
                          reject:(RCTPromiseRejectBlock)reject {
  [[ThingSmartSceneManager sharedInstance] getCityListWithCountryCode:countryCode
                                                              success:^(NSArray<ThingSmartCityModel *> *list) {
    NSMutableArray *out = [NSMutableArray array];
    for (ThingSmartCityModel *c in list) {
      if ([c isKindOfClass:[ThingSmartCityModel class]]) [out addObject:TuyaSceneCity(c)];
    }
    resolve(out);
  } failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"city_list_error"); }];
}

- (void)getCityByLocation:(double)latitude
                longitude:(double)longitude
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  if (isnan(latitude) || isnan(longitude)) { TuyaSceneInvalid(reject, @"latitude/longitude are required"); return; }
  NSString *lat = [NSString stringWithFormat:@"%.6f", latitude];
  NSString *lon = [NSString stringWithFormat:@"%.6f", longitude];
  [[ThingSmartSceneManager sharedInstance] getCityInfoWithLatitude:lat
                                                         longitude:lon
                                                           success:^(ThingSmartCityModel *model) {
    if (!model) {
      TuyaRejectWithDomain(reject, @"city_not_found", [NSString stringWithFormat:@"No city found for %@,%@", lat, lon], @"sdk");
      return;
    }
    resolve(TuyaSceneCity(model));
  } failure:^(NSError *e) { TuyaSceneRejectError(reject, e, @"city_error"); }];
}

// ---------- Realtime listener ----------
// Chỉ enable/disable (ThingSmartSceneManagerDelegate); add/update/delete không có callback trên iOS.
- (void)registerSceneChangeListener {
  [ThingSmartSceneManager sharedInstance].delegate = self;
}

- (void)unregisterSceneChangeListener {
  if ([ThingSmartSceneManager sharedInstance].delegate == self) {
    [ThingSmartSceneManager sharedInstance].delegate = nil;
  }
}

- (void)sceneManager:(ThingSmartSceneManager *)manager state:(NSString *)state sceneId:(NSString *)sceneId {
  [self emit:kTuyaSceneEvent body:@{ @"type": state ?: @"", @"sceneId": sceneId ?: @"" }];
}

- (void)dealloc {
  [self unregisterSceneChangeListener];
}

// addListener:/removeListeners: kế thừa từ RCTEventEmitter (TuyaEventEmitter).

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaSceneSpecJSI>(params);
}

@end
