import { Tuya } from '@jimmy-vu/react-native-turbo-tuya';
import { Section, Field, Btn } from '../ui';
import type { DemoCtx } from '../useDemo';

export function HomeSection({ d }: { d: DemoCtx }) {
  return (
    <Section title="3 · Home" subtitle="create/list/detail + weather + change listeners">
      <Field label="Home name" value={d.homeName} onChangeText={d.setHomeName} width={180} />
      <Field label="homeId" value={d.homeId} onChangeText={d.setHomeId} width={140} numeric />
      <Btn title="Create home" onPress={d.run('createHome', () => Tuya.createHome(d.homeName, 0, 0, '', []), (h) => d.setHomeId(String(h.homeId)))} />
      <Btn title="List homes" onPress={d.run('getHomeList', () => Tuya.getHomeList(), (l) => l[0] && d.setHomeId(String(l[0].homeId)))} kind="ghost" />
      <Btn title="Home detail" onPress={d.run('getHomeDetail', () => Tuya.getHomeDetail(d.hid()))} kind="ghost" />
      <Btn title="Weather sketch" onPress={d.run('getHomeWeatherSketch', () => Tuya.getHomeWeatherSketch(d.hid(), 0, 0))} kind="ghost" />
      <Btn title="Start change listener" onPress={d.run('startHomeChangeListener', () => Tuya.startHomeChangeListener())} kind="ghost" />
      <Btn title="Start status listener" onPress={d.run('startHomeStatusListener', () => Tuya.startHomeStatusListener(d.hid()))} kind="ghost" />
    </Section>
  );
}
