import { Tuya } from '@jimmy-vu/react-native-turbo-tuya';
import { Section, Field, Btn } from '../ui';
import type { DemoCtx } from '../useDemo';

export function PairingSection({ d }: { d: DemoCtx }) {
  return (
    <Section title="4 · Pairing" subtitle="Wi-Fi EZ/AP · BLE · combo · auto-token (results stream into the log)">
      <Field label="SSID (2.4G)" value={d.ssid} onChangeText={d.setSsid} width={160} />
      <Field label="Wi-Fi pwd" value={d.wifiPassword} onChangeText={d.setWifiPassword} secure />
      <Field label="token" value={d.token} onChangeText={d.setToken} width={160} />
      <Field label="BLE uuid" value={d.uuid} onChangeText={d.setUuid} width={160} />
      <Btn title="Get token" onPress={d.run('getPairingToken', () => Tuya.getPairingToken(d.hid()), (t) => d.setToken(t))} kind="ghost" />
      <Btn title="Wi-Fi EZ (manual token)" onPress={d.run('startWifiPairing', () => Tuya.startWifiPairing('EZ', d.ssid, d.wifiPassword, d.token, 120), (r) => d.setDevId(r.devId))} />
      <Btn title="Wi-Fi EZ (auto-token)" onPress={d.run('startWifiPairingAuto', () => Tuya.startWifiPairingAuto(d.hid(), 'EZ', d.ssid, d.wifiPassword, 120), (r) => d.setDevId(r.devId))} />
      <Btn
        title="BLE scan start"
        onPress={() => {
          Tuya.startBleScan(60);
          d.push('startBleScan', 'scanning… (see evt:bleScan)', 'ok');
        }}
        kind="ghost"
      />
      <Btn
        title="BLE scan stop"
        onPress={() => {
          Tuya.stopBleScan();
          d.push('stopBleScan', 'invoked (void)', 'ok');
        }}
        kind="ghost"
      />
      <Btn title="Combo BLE+Wi-Fi (auto-token)" onPress={d.run('startBleWifiPairing', () => Tuya.startBleWifiPairing(d.hid(), d.uuid, d.ssid, d.wifiPassword, 120), (r) => d.setDevId(r.devId))} />
    </Section>
  );
}
