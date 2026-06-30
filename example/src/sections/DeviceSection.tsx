import { Tuya } from '@jimmy-vu/react-native-turbo-tuya';
import { Section, Field, Btn } from '../ui';
import type { DemoCtx } from '../useDemo';

export function DeviceSection({ d }: { d: DemoCtx }) {
  return (
    <Section title="5 · Device + OTA" subtitle="DP control + status (set ice-bath target temperature) + firmware">
      <Field label="devId" value={d.devId} onChangeText={d.setDevId} width={200} />
      <Field label="DP id" value={d.dpId} onChangeText={d.setDpId} width={80} numeric />
      <Field label="Target °C" value={d.targetTemp} onChangeText={d.setTargetTemp} width={90} numeric />
      <Btn title="Snapshot" onPress={d.run('getDeviceSnapshot', () => Tuya.getDeviceSnapshot(d.devId))} kind="ghost" />
      <Btn title="Get DPs" onPress={d.run('getDps', () => Tuya.getDps(d.devId))} kind="ghost" />
      <Btn title="Is online?" onPress={d.run('isDeviceOnline', () => Tuya.isDeviceOnline(d.devId))} kind="ghost" />
      <Btn
        title="Listen status"
        onPress={() => {
          Tuya.registerDeviceListener(d.devId);
          d.push('registerDeviceListener', 'listening… (see evt:deviceStatus)', 'ok');
        }}
        kind="ghost"
      />
      <Btn
        title="Stop listen"
        onPress={() => {
          Tuya.unregisterDeviceListener(d.devId);
          d.push('unregisterDeviceListener', 'invoked (void)', 'ok');
        }}
        kind="ghost"
      />
      <Btn title="Set target temp" onPress={d.run('publishDps', () => Tuya.publishDps(d.devId, d.tempDps()))} />
      <Btn title="Set temp + await ack" onPress={d.run('publishDpsAwaitAck', () => Tuya.publishDpsAwaitAck(d.devId, d.tempDps(), 8000))} />
      <Btn title="Check upgrade" onPress={d.run('checkFirmwareUpgrade', () => Tuya.checkFirmwareUpgrade(d.devId))} kind="ghost" />
      <Btn title="Auto-upgrade switch" onPress={d.run('getAutoUpgradeSwitch', () => Tuya.getAutoUpgradeSwitch(d.devId))} kind="ghost" />
      <Btn title="Start upgrade (all)" onPress={d.run('startFirmwareUpgrade', () => Tuya.startFirmwareUpgrade(d.devId, []))} />
    </Section>
  );
}
