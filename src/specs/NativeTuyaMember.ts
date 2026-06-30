import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaMember — quản lý thành viên home + lời mời + chuyển chủ. KHÔNG phát event.
// (P3 — dự phòng: app ice-bath 1 home/user thường chỉ cần share điều khiển cho người nhà.)
export type Member = {
  memberId: number;
  account: string;
  name: string; // nickName
  admin: boolean;
  role: number; // 2 owner / 1 admin / 0 member / -1 custom / -999 invalid
  status: number; // dealStatus: 1 pending / 2 accepted / 3 rejected
  headPic: string;
  mobile: string;
  invitationCode: string;
};

export type InvitationResult = {
  invitationId: number;
  code: string;
};

export interface Spec extends TurboModule {
  // --- Member CRUD ---
  queryMembers(homeId: number): Promise<Member[]>;
  // role: 2 owner/1 admin/0 member; autoAccept=true thêm thẳng, false tạo lời mời chờ accept.
  addMember(
    homeId: number,
    account: string,
    countryCode: string,
    name: string,
    role: number,
    admin: boolean,
    autoAccept: boolean
  ): Promise<Member>;
  updateMember(
    homeId: number,
    memberId: number,
    name: string,
    admin: boolean
  ): Promise<void>;
  removeMember(homeId: number, memberId: number): Promise<void>;

  // --- Invitation (mời theo invite code) ---
  createInvitation(homeId: number): Promise<InvitationResult>;
  getInvitationList(homeId: number): Promise<string>; // JSON (bean field chưa verbatim)
  cancelInvitation(invitationId: number): Promise<void>;
  updateInvitedMember(
    invitationId: number,
    memberName: string,
    memberRole: number
  ): Promise<void>;
  joinHomeByCode(code: string): Promise<void>;
  // accept=true chấp nhận / false từ chối lời mời (iOS joinFamilyWithAccept).
  processInvitation(homeId: number, accept: boolean): Promise<void>;

  // --- Transfer owner (chỉ owner; member phải đã có trong home) ---
  transferHomeOwner(homeId: number, memberId: number): Promise<void>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaMember');
