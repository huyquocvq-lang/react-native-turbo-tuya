import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaMessage — gộp Message Center + Push status + Do-Not-Disturb. KHÔNG phát event.
// type (message): 'alarm' | 'family' | 'notification'. pushType: + 'marketing'.
export type TuyaMessageItem = {
  id: string;
  msgType: string;
  msgSrcId: string; // devId nguồn ('' nếu không có)
  title: string;
  content: string;
  typeContent: string;
  icon: string;
  dateTime: string;
  hasNotRead: boolean;
};

export type TuyaMessagePage = {
  list: TuyaMessageItem[];
  offset: number;
  limit: number;
  hasMore: boolean; // suy ra khi số phần tử < limit
};

export type TuyaMessageHasNew = {
  alarm: boolean;
  family: boolean;
  notification: boolean;
};

export type TuyaDndPeriod = {
  id: number; // timerId
  startTime: string; // 'HH:mm' (recurring) | 'YYYY-MM-DD HH:mm' (once)
  endTime: string;
  loops: string; // 7 ký tự; '' nếu once
  allDevices: boolean;
  devIds: string[];
};

export interface Spec extends TurboModule {
  // --- Push token ---
  registerDevice(token: string, provider: string): Promise<void>; // provider: 'fcm' | 'apns'
  unregisterDevice(): Promise<void>;

  // --- Message list / detail ---
  getMessageList(offset: number, limit: number): Promise<TuyaMessagePage>;
  getMessageListByType(
    type: string,
    offset: number,
    limit: number
  ): Promise<TuyaMessagePage>;
  getMessageDetailList(
    type: string,
    msgSrcId: string,
    offset: number,
    limit: number
  ): Promise<TuyaMessagePage>;

  // --- Has-new / read / delete ---
  getMessageHasNew(): Promise<TuyaMessageHasNew>;
  markMessagesRead(type: string, ids: string[]): Promise<boolean>; // iOS có API; Android best-effort
  deleteMessages(ids: string[]): Promise<boolean>;
  deleteMessagesByType(
    type: string,
    ids: string[],
    srcIds: string[]
  ): Promise<boolean>;

  // --- Push status ---
  getPushStatus(): Promise<boolean>;
  setPushStatus(open: boolean): Promise<boolean>;
  getPushStatusByType(pushType: string): Promise<boolean>;
  setPushStatusByType(pushType: string, open: boolean): Promise<boolean>;

  // --- Do-Not-Disturb ---
  getDndStatus(): Promise<boolean>;
  setDndStatus(open: boolean): Promise<boolean>;
  getDndList(): Promise<TuyaDndPeriod[]>; // recurring
  getOnceDndList(): Promise<TuyaDndPeriod[]>; // one-time
  addDnd(
    startTime: string,
    endTime: string,
    loops: string,
    allDevices: boolean,
    devIds: string[]
  ): Promise<number>; // -> timerId
  addOnceDnd(
    startTime: string,
    endTime: string,
    allDevices: boolean,
    devIds: string[]
  ): Promise<number>;
  modifyDnd(
    dndId: number, // KHÔNG đặt tên 'id' — keyword ObjC sẽ vỡ selector
    startTime: string,
    endTime: string,
    loops: string,
    allDevices: boolean,
    devIds: string[]
  ): Promise<boolean>;
  removeDnd(dndId: number): Promise<boolean>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaMessage');
