#import "TuyaMember.h"

// TuyaMember (iOS) — TODO-reject. Wire trên Xcode (ThingSmartHome member API):
//   query: getHomeMemberListWithSuccess: ; add: addHomeMemberWithAddMemeberRequestModel: ;
//   update: updateHomeMemberInfoWithMemberRequestModel: ; remove: removeHomeMemberWithMemberId: ;
//   invitation: (Biz ThingSmartMemberBiz) ; process: joinFamilyWithAccept: ;
//   transfer: transferHomeWithMemberId: . Verbatim: docs/research/tuya-home-sdk-home-management.md.
static void TuyaTODO(NSString *what, RCTPromiseRejectBlock reject) {
  reject(@"ios_todo",
         [NSString stringWithFormat:@"iOS '%@' chưa wire — xem docs/research/tuya-home-sdk-home-management.md.", what],
         nil);
}

@implementation TuyaMember

RCT_EXPORT_MODULE()

// ---------- Member CRUD ----------
- (void)queryMembers:(double)homeId
             resolve:(RCTPromiseResolveBlock)resolve
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"queryMembers", reject); }

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
              reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"removeMember", reject); }

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
                   reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"processInvitation", reject); }

// ---------- Transfer owner ----------
- (void)transferHomeOwner:(double)homeId
                 memberId:(double)memberId
                  resolve:(RCTPromiseResolveBlock)resolve
                   reject:(RCTPromiseRejectBlock)reject { TuyaTODO(@"transferHomeOwner", reject); }

// ---------- TurboModule boilerplate ----------
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeTuyaMemberSpecJSI>(params);
}

+ (NSString *)moduleName { return @"TuyaMember"; }

@end
