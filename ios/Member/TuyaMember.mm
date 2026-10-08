#import "TuyaMember.h"
#import "TuyaReject.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaMember (iOS) - WIRED: queryMembers/addMember (ThingSmartHome) + updateMember/removeMember/transferHomeOwner
// (ThingSmartHomeMember - KHÔNG phải ThingSmartHome) + lời mời create/list/cancel/updateInvited/joinByCode
// (ThingSmartHomeInvitation) + processInvitation (joinFamilyWithAccept: - trên ThingSmartHome).
// Selector verify trên header ThingSmartDeviceKit 5.14.6. Verbatim: docs/research/tuya-home-sdk-home-management.md.
// Model đã verify header: có memberId/userName/name/role/dealStatus/headPic/mobile; KHÔNG có account/invitationCode,
// isAdmin deprecated → suy "admin" từ role (Member=0 < Admin=1 < Owner=2).

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

static NSString *TuyaJSONString(id obj, NSString *fallback) {
  if (![NSJSONSerialization isValidJSONObject:obj]) return fallback;
  NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : fallback;
}

static NSDictionary *TuyaMemberMap(ThingSmartHomeMemberModel *m) {
  return @{
    @"memberId": @(m.memberId),
    @"account": m.userName ?: @"",
    @"name": m.name ?: @"",
    @"admin": @(m.role >= ThingHomeRoleType_Admin),
    @"role": @(m.role),
    @"status": @(m.dealStatus),
    @"headPic": m.headPic ?: @"",
    @"mobile": m.mobile ?: @"",
    @"invitationCode": @"",
  };
}

// Shape lời mời chuẩn hoá 2 nền tảng (Android map từ InviteListResponseBean cùng key).
// validTime: hiệu lực mã mời (giờ); dealStatus: 1 chờ / 2 đồng ý / 3 từ chối.
static NSDictionary *TuyaInvitationMap(ThingSmartHomeInvitationRecordModel *r) {
  return @{
    @"invitationId": r.invitationID ?: @0,
    @"invitationCode": r.invitationCode ?: @"",
    @"name": r.name ?: @"",
    @"role": @(r.role),
    @"dealStatus": @(r.dealStatus),
    @"validTime": @(r.validTime),
  };
}

@interface TuyaMember ()
@property (nonatomic, strong) ThingSmartHomeMember *homeMember;
@property (nonatomic, strong) ThingSmartHomeInvitation *homeInvitation;
@end

@implementation TuyaMember

RCT_EXPORT_MODULE()

- (ThingSmartHomeMember *)homeMember {
  if (!_homeMember) { _homeMember = [[ThingSmartHomeMember alloc] init]; }
  return _homeMember;
}

- (ThingSmartHomeInvitation *)homeInvitation {
  if (!_homeInvitation) { _homeInvitation = [[ThingSmartHomeInvitation alloc] init]; }
  return _homeInvitation;
}

- (ThingSmartHome *)homeOf:(double)homeId {
  return [ThingSmartHome homeWithHomeId:(long long)homeId];
}

// ---------- Member CRUD ----------
- (void)queryMembers:(double)homeId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [self homeOf:homeId];
  if (!home) { reject(@"no_home", @"Không tìm thấy home", nil); return; }
  [home getHomeMemberListWithSuccess:^(NSArray<ThingSmartHomeMemberModel *> *list) {
    NSMutableArray *out = [NSMutableArray array];
    for (ThingSmartHomeMemberModel *m in list) { [out addObject:TuyaMemberMap(m)]; }
    resolve(out);
  } failure:^(NSError *e) { reject(@"member_list_error", e.localizedDescription, e); }];
}

- (void)addMember:(double)homeId
          account:(NSString *)account
      countryCode:(NSString *)countryCode
             name:(NSString *)name
             role:(double)role
            admin:(BOOL)admin
       autoAccept:(BOOL)autoAccept
          resolve:(RCTPromiseResolveBlock)resolve
           reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [self homeOf:homeId];
  if (!home) { TuyaRejectWithDomain(reject, @"no_home", @"Home not found.", @"sdk"); return; }
  // iOS phân quyền bằng role; cờ `admin` không có trong request model (Android SDK cũng KHÔNG gửi admin) → bỏ qua.
  NSInteger roleValue = (NSInteger)role;
  ThingSmartHomeAddMemberRequestModel *req = [[ThingSmartHomeAddMemberRequestModel alloc] init];
  req.name = name;
  req.account = account;
  req.countryCode = countryCode;
  req.role = (ThingHomeRoleType)roleValue;
  req.autoAccept = autoAccept;
  [home addHomeMemberWithAddMemeberRequestModel:req success:^(NSDictionary *dict) {
    // Server chỉ trả memberId (+ headPic): đọc đúng 2 key mà ThingSmartMemberBiz (FamilyBizKit) đọc từ dict này.
    // role/admin/status suy từ request (giống Android): status = autoAccept ? 2 đã nhận : 1 chờ xác nhận.
    NSDictionary *d = [dict isKindOfClass:[NSDictionary class]] ? dict : @{};
    id memberId = d[@"memberId"];
    id headPic = d[@"headPic"];
    resolve(@{
      @"memberId": @([memberId respondsToSelector:@selector(longLongValue)] ? [memberId longLongValue] : 0LL),
      @"account": account ?: @"",
      @"name": name ?: @"",
      @"admin": @(roleValue >= ThingHomeRoleType_Admin),
      @"role": @(roleValue),
      @"status": @(autoAccept ? ThingHomeStatusAccept : ThingHomeStatusPending),
      @"headPic": [headPic isKindOfClass:[NSString class]] ? headPic : @"",
      @"mobile": @"",
      @"invitationCode": @"",
    });
  } failure:^(NSError *e) { TuyaRejectNSError(reject, e, @"add_member_error", @"Failed to add home member."); }];
}

- (void)updateMember:(double)homeId
            memberId:(double)memberId
                name:(NSString *)name
               admin:(BOOL)admin
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [self homeOf:homeId];
  if (!home) { TuyaRejectWithDomain(reject, @"no_home", @"Home not found.", @"sdk"); return; }
  long long mid = (long long)memberId;
  ThingSmartHomeMember *api = self.homeMember;
  // iOS cập nhật theo role (Android gửi cờ admin) → đọc role hiện tại trước: chỉ đổi Member↔Admin khi cờ admin
  // thực sự khác; owner luôn giữ nguyên (ThingHomeRoleType_Unknown = không cập nhật role) để không hạ quyền owner.
  [home getHomeMemberListWithSuccess:^(NSArray<ThingSmartHomeMemberModel *> *list) {
    ThingSmartHomeMemberModel *current = nil;
    for (ThingSmartHomeMemberModel *m in list) {
      if (m.memberId == mid) { current = m; break; }
    }
    BOOL keepRole = current && (current.role == ThingHomeRoleType_Owner ||
                                (current.role >= ThingHomeRoleType_Admin) == admin);
    ThingSmartHomeMemberRequestModel *req = [[ThingSmartHomeMemberRequestModel alloc] init];
    req.memberId = mid;
    if (name.length > 0) { req.name = name; } // nil = giữ tên cũ (theo header)
    req.role = keepRole ? ThingHomeRoleType_Unknown
                        : (admin ? ThingHomeRoleType_Admin : ThingHomeRoleType_Member);
    [api updateHomeMemberInfoWithMemberRequestModel:req
                                            success:^{ resolve(nil); }
                                            failure:^(NSError *e) {
      TuyaRejectNSError(reject, e, @"update_member_error", @"Failed to update home member.");
    }];
  } failure:^(NSError *e) { TuyaRejectNSError(reject, e, @"update_member_error", @"Failed to load home members."); }];
}

- (void)removeMember:(double)homeId
            memberId:(double)memberId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  // API iOS chỉ cần memberId (homeId từ JS không dùng - member id là global).
  [self.homeMember removeHomeMemberWithMemberId:(long long)memberId
                                        success:^{ resolve(nil); }
                                        failure:^(NSError *e) { reject(@"remove_member_error", e.localizedDescription, e); }];
}

// ---------- Invitation ----------
- (void)createInvitation:(double)homeId
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  long long hid = (long long)homeId;
  ThingSmartHomeInvitation *api = self.homeInvitation;
  ThingSmartHomeInvitationCreateRequestModel *req = [[ThingSmartHomeInvitationCreateRequestModel alloc] init];
  req.homeID = hid;
  req.needMsgContent = YES;            // giống Android (isMsgContent = true); message không trả về JS
  req.role = ThingHomeRoleType_Member; // mời với vai trò member - giống Android
  [api createInvitationWithCreateRequestModel:req success:^(ThingSmartHomeInvitationResultModel *result) {
    NSString *code = result.invitationCode ?: @"";
    if (code.length == 0) {
      TuyaRejectWithDomain(reject, @"create_invitation_error", @"SDK returned no invitation code.", @"sdk");
      return;
    }
    // SDK chỉ trả invitationCode (+ msg) - không có invitationID → tra danh sách lời mời theo mã vừa tạo.
    // Mã đã tạo thành công nên KHÔNG reject khi tra lỗi/không thấy → invitationId = 0 (JS gọi getInvitationList).
    [api fetchInvitationRecordListWithHomeID:hid success:^(NSArray<ThingSmartHomeInvitationRecordModel *> *list) {
      NSNumber *invitationId = @0;
      for (ThingSmartHomeInvitationRecordModel *r in list) {
        if ([code isEqual:r.invitationCode] && r.invitationID) { invitationId = r.invitationID; break; }
      }
      resolve(@{ @"invitationId": invitationId, @"code": code });
    } failure:^(NSError *e) {
      resolve(@{ @"invitationId": @0, @"code": code });
    }];
  } failure:^(NSError *e) { TuyaRejectNSError(reject, e, @"create_invitation_error", @"Failed to create invitation."); }];
}

- (void)getInvitationList:(double)homeId
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  [self.homeInvitation fetchInvitationRecordListWithHomeID:(long long)homeId
                                                   success:^(NSArray<ThingSmartHomeInvitationRecordModel *> *list) {
    NSMutableArray *out = [NSMutableArray array];
    for (ThingSmartHomeInvitationRecordModel *r in list) { [out addObject:TuyaInvitationMap(r)]; }
    resolve(TuyaJSONString(out, @"[]"));
  } failure:^(NSError *e) { TuyaRejectNSError(reject, e, @"invitation_list_error", @"Failed to load invitations."); }];
}

- (void)cancelInvitation:(double)invitationId
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject {
  [self.homeInvitation cancelInvitationWithInvitationID:@((long long)invitationId)
                                                success:^(BOOL result) { resolve(nil); }
                                                failure:^(NSError *e) {
    TuyaRejectNSError(reject, e, @"cancel_invitation_error", @"Failed to cancel invitation.");
  }];
}

- (void)updateInvitedMember:(double)invitationId
                 memberName:(NSString *)memberName
                 memberRole:(double)memberRole
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHomeInvitationInfoRequestModel *req = [[ThingSmartHomeInvitationInfoRequestModel alloc] init];
  req.invitationID = @((long long)invitationId);
  req.name = memberName;
  req.role = (ThingHomeRoleType)(NSInteger)memberRole;
  [self.homeInvitation updateInvitationInfoWithInvitationInfoRequestModel:req
                                                                  success:^(BOOL result) { resolve(nil); }
                                                                  failure:^(NSError *e) {
    TuyaRejectNSError(reject, e, @"update_invited_error", @"Failed to update invitation.");
  }];
}

- (void)joinHomeByCode:(NSString *)code
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject {
  // Tương đương Android IThingHomeManager.joinHomeByInviteCode (thing.m.group.invitation.member.add).
  [self.homeInvitation joinHomeWithInvitationCode:code
                                          success:^(BOOL result) { resolve(nil); }
                                          failure:^(NSError *e) {
    TuyaRejectNSError(reject, e, @"join_home_error", @"Failed to join home with invitation code.");
  }];
}

- (void)processInvitation:(double)homeId
                   accept:(BOOL)accept
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  ThingSmartHome *home = [self homeOf:homeId];
  if (!home) { reject(@"no_home", @"Không tìm thấy home", nil); return; }
  [home joinFamilyWithAccept:accept
                     success:^(BOOL result) { resolve(nil); }
                     failure:^(NSError *e) { reject(@"process_invitation_error", e.localizedDescription, e); }];
}

// ---------- Transfer owner ----------
- (void)transferHomeOwner:(double)homeId
                 memberId:(double)memberId
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject {
  // API iOS chỉ cần memberId (homeId từ JS không dùng - member id là global).
  [self.homeMember transferHomeWithMemberId:(long long)memberId
                                    success:^{ resolve(nil); }
                                    failure:^(NSError *e) { reject(@"transfer_owner_error", e.localizedDescription, e); }];
}

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaMemberSpecJSI>(params);
}

@end
