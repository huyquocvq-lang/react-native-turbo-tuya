#import "TuyaMember.h"
#import <ThingSmartHomeKit/ThingSmartKit.h>

// TuyaMember (iOS) — WIRED: queryMembers (getHomeMemberListWithSuccess:) + removeMember + transferHomeOwner
// (2 cái sau nằm trên class ThingSmartHomeMember, KHÔNG phải ThingSmartHome — đã verify header ThingSmartDeviceKit)
// + processInvitation (joinFamilyWithAccept: — trên ThingSmartHome). Verbatim: docs/research/tuya-home-sdk-home-management.md.
// TODO: addMember/updateMember (request model field chưa verbatim), invitation create/list/cancel/updateInvited/joinByCode (Biz).
// Model đã verify header: có memberId/userName/name/role/dealStatus/headPic/mobile; KHÔNG có account/invitationCode,
// isAdmin deprecated → suy "admin" từ role (Member=0 < Admin=1 < Owner=2).
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-home-management.md.", what],
         nil);
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

@interface TuyaMember ()
@property (nonatomic, strong) ThingSmartHomeMember *homeMember;
@end

@implementation TuyaMember

RCT_EXPORT_MODULE()

- (ThingSmartHomeMember *)homeMember {
  if (!_homeMember) { _homeMember = [[ThingSmartHomeMember alloc] init]; }
  return _homeMember;
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
           reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"addMember", reject); }

- (void)updateMember:(double)homeId
            memberId:(double)memberId
                name:(NSString *)name
               admin:(BOOL)admin
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"updateMember", reject); }

- (void)removeMember:(double)homeId
            memberId:(double)memberId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject {
  // API iOS chỉ cần memberId (homeId từ JS không dùng — member id là global).
  [self.homeMember removeHomeMemberWithMemberId:(long long)memberId
                                        success:^{ resolve(nil); }
                                        failure:^(NSError *e) { reject(@"remove_member_error", e.localizedDescription, e); }];
}

// ---------- Invitation ----------
- (void)createInvitation:(double)homeId
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"createInvitation", reject); }

- (void)getInvitationList:(double)homeId
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"getInvitationList", reject); }

- (void)cancelInvitation:(double)invitationId
                 resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"cancelInvitation", reject); }

- (void)updateInvitedMember:(double)invitationId
                 memberName:(NSString *)memberName
                 memberRole:(double)memberRole
                    resolve:(RCTPromiseResolveBlock)resolve
                     reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"updateInvitedMember", reject); }

- (void)joinHomeByCode:(NSString *)code
               resolve:(RCTPromiseResolveBlock)resolve
                reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"joinHomeByCode", reject); }

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
  // API iOS chỉ cần memberId (homeId từ JS không dùng — member id là global).
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
