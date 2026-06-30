import { TurboModuleRegistry } from 'react-native';
import type { TurboModule } from 'react-native';

// TurboModule: TuyaTimer — hẹn giờ / lịch cloud cho device (hoặc group). KHÔNG phát event.
// inputJson (add/update) = JSON object:
//   { taskName: string; bizId: string; bizType: 'device'|'group'; time: 'HH:mm'; loops: '1111111' (7 ký tự);
//     dpsJson: '{"1":true}'; status: boolean; appPush?: boolean; aliasName?: string; timezone?: string }
// bizType: 'device' | 'group'. op (updateTimerStatus): 'open' | 'close' | 'delete'.
export type TimerItem = {
  timerId: string;
  time: string; // 'HH:mm'
  loops: string; // 7 ký tự (T2..CN); '0000000'=một lần, '1111111'=hằng ngày
  status: boolean;
  dpsJson: string;
  aliasName: string;
};

export interface Spec extends TurboModule {
  addTimer(inputJson: string): Promise<void>;
  updateTimer(timerId: string, inputJson: string): Promise<void>;
  removeTimer(
    taskName: string,
    bizId: string,
    bizType: string,
    timerIds: string[]
  ): Promise<void>;
  getTimerList(
    taskName: string,
    bizId: string,
    bizType: string
  ): Promise<TimerItem[]>;
  updateTimerStatus(
    taskName: string,
    bizId: string,
    bizType: string,
    timerIds: string[],
    op: string
  ): Promise<void>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TuyaTimer');
