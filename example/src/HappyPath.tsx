import { useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Tuya } from '@jimmy-vu/react-native-turbo-tuya';
import { Section, Field, Btn, fmt, errText } from './ui';
import type { DemoCtx } from './useDemo';

type StepStatus = 'idle' | 'running' | 'ok' | 'err';
type StepState = { status: StepStatus; detail: string };

const STEPS: { key: string; label: string }[] = [
  { key: 'init', label: 'Init SDK' },
  { key: 'login', label: 'Login (email + password)' },
  { key: 'home', label: 'Ensure home (list → create if none)' },
  { key: 'token', label: 'Get pairing token' },
  { key: 'pair', label: 'Pair device (Wi-Fi EZ, auto-token)' },
  { key: 'snapshot', label: 'Read device snapshot' },
  { key: 'settemp', label: 'Set target temperature' },
];

const ICON: Record<StepStatus, string> = { idle: '○', running: '◐', ok: '●', err: '✕' };
const STATUS_COLOR: Record<StepStatus, string> = {
  idle: '#9aa',
  running: '#d9a441',
  ok: '#3fbf6f',
  err: '#d1453b',
};

// Auto-runs the ice-bath happy path end-to-end, stopping at the first failure.
export function HappyPath({ d }: { d: DemoCtx }) {
  const [steps, setSteps] = useState<Record<string, StepState>>({});
  const [running, setRunning] = useState(false);

  const set = (key: string, status: StepStatus, detail = '') =>
    setSteps((prev) => ({ ...prev, [key]: { status, detail } }));

  const step = async <T,>(key: string, fn: () => Promise<T>): Promise<T> => {
    set(key, 'running');
    d.push(`hp:${key}`, 'calling…', 'in');
    try {
      const r = await fn();
      set(key, 'ok', fmt(r));
      d.push(`hp:${key}`, fmt(r), 'ok');
      return r;
    } catch (e) {
      set(key, 'err', errText(e));
      d.push(`hp:${key}`, errText(e), 'err');
      throw e;
    }
  };

  const runAll = async () => {
    setSteps({});
    setRunning(true);
    try {
      await step('init', () => Tuya.initSdk());
      await step('login', () => Tuya.loginWithEmail(d.countryCode, d.email, d.password));
      const home = await step('home', async () => {
        const list = await Tuya.getHomeList();
        return list.length ? list[0]! : Tuya.createHome(d.homeName, 0, 0, '', []);
      });
      const homeId = home.homeId;
      d.setHomeId(String(homeId));
      const token = await step('token', () => Tuya.getPairingToken(homeId));
      d.setToken(token);
      const device = await step('pair', () =>
        Tuya.startWifiPairingAuto(homeId, 'EZ', d.ssid, d.wifiPassword, 120)
      );
      const devId = device.devId;
      d.setDevId(devId);
      await step('snapshot', () => Tuya.getDeviceSnapshot(devId));
      await step('settemp', () =>
        Tuya.publishDps(devId, JSON.stringify({ [d.dpId]: Number(d.targetTemp) }))
      );
    } catch {
      // step() already recorded the failure + logged it; chain stops here.
    } finally {
      setRunning(false);
    }
  };

  return (
    <View>
      <Section title="Happy path" subtitle="Init → Login → Home → Token → Pair → Snapshot → Set temp">
        <Field label="Country" value={d.countryCode} onChangeText={d.setCountryCode} width={80} numeric />
        <Field label="Email" value={d.email} onChangeText={d.setEmail} width={200} placeholder="you@mail.com" />
        <Field label="Password" value={d.password} onChangeText={d.setPassword} secure />
        <Field label="SSID (2.4G)" value={d.ssid} onChangeText={d.setSsid} width={160} />
        <Field label="Wi-Fi pwd" value={d.wifiPassword} onChangeText={d.setWifiPassword} secure />
        <Field label="Target °C" value={d.targetTemp} onChangeText={d.setTargetTemp} width={90} numeric />
        <Btn title={running ? 'Running…' : 'Run happy path'} onPress={running ? () => {} : runAll} />
      </Section>

      <View style={styles.steps}>
        {STEPS.map((s, i) => {
          const st = steps[s.key]?.status ?? 'idle';
          const detail = steps[s.key]?.detail ?? '';
          return (
            <View key={s.key} style={styles.step}>
              <Text style={[styles.icon, { color: STATUS_COLOR[st] }]}>{ICON[st]}</Text>
              <View style={styles.stepBody}>
                <Text style={styles.stepLabel}>
                  {i + 1}. {s.label}
                </Text>
                {detail ? (
                  <Text style={[styles.stepDetail, st === 'err' && styles.stepDetailErr]} numberOfLines={3}>
                    {detail}
                  </Text>
                ) : null}
              </View>
            </View>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  steps: { marginTop: 4, gap: 8 },
  step: { flexDirection: 'row', gap: 10, alignItems: 'flex-start' },
  icon: { fontSize: 18, width: 20, textAlign: 'center', marginTop: 1 },
  stepBody: { flex: 1 },
  stepLabel: { fontSize: 13, color: '#16324f', fontWeight: '600' },
  stepDetail: { fontSize: 11, color: '#5a7', marginTop: 1 },
  stepDetailErr: { color: '#d1453b' },
});
