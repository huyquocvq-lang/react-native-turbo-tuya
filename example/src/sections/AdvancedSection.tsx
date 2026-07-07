import { Tuya } from '@jimmy-vu/react-native-turbo-tuya';
import { Section, Btn } from '../ui';
import type { DemoCtx } from '../useDemo';

// Scene + Timer/Message/Member + Matter/Mesh. Several are TODO/skeleton on Android → reject (by design).
export function AdvancedSection({ d }: { d: DemoCtx }) {
  return (
    <Section title="6 · Scene · Timer · Message · Member · Matter · Mesh" subtitle="P2/P3 - some methods reject with not_implemented (intended-call documented in source)">
      <Btn title="Scene list" onPress={d.run('getSceneList', () => Tuya.getSceneList(d.hid()))} kind="ghost" />
      <Btn title="Timer list" onPress={d.run('getTimerList', () => Tuya.getTimerList('', d.devId, 1))} kind="ghost" />
      <Btn title="Push ON" onPress={d.run('setPushStatus', () => Tuya.setPushStatus(true))} kind="ghost" />
      <Btn title="DND OFF" onPress={d.run('setDndStatus', () => Tuya.setDndStatus(false))} kind="ghost" />
      <Btn title="Query members" onPress={d.run('queryMembers', () => Tuya.queryMembers(d.hid()))} kind="ghost" />
      <Btn title="Parse Matter code" onPress={d.run('parseMatterSetupCode', () => Tuya.parseMatterSetupCode('MT:Y.K9042C00KA0648G00'))} kind="ghost" />
      <Btn title="Mesh list" onPress={d.run('getMeshList', () => Tuya.getMeshList(d.hid()))} kind="ghost" />
    </Section>
  );
}
