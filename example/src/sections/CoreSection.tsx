import { Tuya } from '@jimmy-vu/react-native-turbo-tuya';
import { Section, Btn } from '../ui';
import type { DemoCtx } from '../useDemo';

export function CoreSection({ d }: { d: DemoCtx }) {
  return (
    <Section title="1 · Core" subtitle="initSdk reads native config — no key from JS">
      <Btn title="Init SDK" onPress={d.run('initSdk', () => Tuya.initSdk())} />
      <Btn title="Version" onPress={d.run('getSdkVersion', () => Tuya.getSdkVersion())} kind="ghost" />
      <Btn
        title="Destroy"
        onPress={() => {
          Tuya.destroySdk();
          d.push('destroySdk', 'invoked (void)', 'ok');
        }}
        kind="ghost"
      />
    </Section>
  );
}
