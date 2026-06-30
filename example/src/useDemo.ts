import { useEffect, useState } from 'react';
import {
  onDeviceStatus,
  onPairingProgress,
  onBleScan,
  onSessionExpired,
  onOtaProgress,
  onOtaStatusChanged,
  onOtaSuccess,
  onOtaFailure,
  onSceneChange,
  onHomeChange,
  onMatterDeviceFound,
  onMatterError,
  onMeshDeviceFound,
} from '@jimmy-vu/react-native-turbo-tuya';
import { useConsole, useRun, fmt, type LogKind, type LogLine } from './ui';

export type Push = (tag: string, text: string, kind?: LogKind) => void;
export type Run = <T>(
  label: string,
  fn: () => Promise<T>,
  onResult?: (r: T) => void
) => () => Promise<void>;

// Shared demo context: all inputs + setters + the run/push helpers, passed to each section.
export interface DemoCtx {
  countryCode: string;
  setCountryCode: (s: string) => void;
  email: string;
  setEmail: (s: string) => void;
  password: string;
  setPassword: (s: string) => void;
  code: string;
  setCode: (s: string) => void;

  homeName: string;
  setHomeName: (s: string) => void;
  homeId: string;
  setHomeId: (s: string) => void;

  ssid: string;
  setSsid: (s: string) => void;
  wifiPassword: string;
  setWifiPassword: (s: string) => void;
  token: string;
  setToken: (s: string) => void;
  uuid: string;
  setUuid: (s: string) => void;

  devId: string;
  setDevId: (s: string) => void;
  dpId: string;
  setDpId: (s: string) => void;
  targetTemp: string;
  setTargetTemp: (s: string) => void;

  hid: () => number;
  tempDps: () => string;
  run: Run;
  push: Push;
}

export function useDemo(): { d: DemoCtx; lines: LogLine[]; clear: () => void } {
  const { lines, push, clear } = useConsole();
  const run = useRun(push);

  const [countryCode, setCountryCode] = useState('49'); // EU (e.g. Germany)
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');

  const [homeName, setHomeName] = useState('Ice Bath Home');
  const [homeId, setHomeId] = useState('');

  const [ssid, setSsid] = useState('');
  const [wifiPassword, setWifiPassword] = useState('');
  const [token, setToken] = useState('');
  const [uuid, setUuid] = useState('');

  const [devId, setDevId] = useState('');
  const [dpId, setDpId] = useState('104'); // ice-bath target-temp DP (example)
  const [targetTemp, setTargetTemp] = useState('20');

  // Live event log: subscribe once; auto-capture BLE uuid for pairing.
  useEffect(() => {
    const evt = (name: string) => (e: unknown) => push(`evt:${name}`, fmt(e), 'evt');
    const subs = [
      onDeviceStatus(evt('deviceStatus')),
      onPairingProgress(evt('pairingProgress')),
      onBleScan((e) => {
        push('evt:bleScan', fmt(e), 'evt');
        if (e.uuid) setUuid(e.uuid);
      }),
      onSessionExpired(evt('sessionExpired')),
      onOtaProgress(evt('otaProgress')),
      onOtaStatusChanged(evt('otaStatus')),
      onOtaSuccess(evt('otaSuccess')),
      onOtaFailure(evt('otaFailure')),
      onSceneChange(evt('sceneChange')),
      onHomeChange(evt('homeChange')),
      onMatterDeviceFound(evt('matterFound')),
      onMatterError(evt('matterError')),
      onMeshDeviceFound(evt('meshFound')),
    ];
    return () => subs.forEach((s) => s.remove());
  }, [push]);

  const d: DemoCtx = {
    countryCode, setCountryCode,
    email, setEmail,
    password, setPassword,
    code, setCode,
    homeName, setHomeName,
    homeId, setHomeId,
    ssid, setSsid,
    wifiPassword, setWifiPassword,
    token, setToken,
    uuid, setUuid,
    devId, setDevId,
    dpId, setDpId,
    targetTemp, setTargetTemp,
    hid: () => Number(homeId),
    tempDps: () => JSON.stringify({ [dpId]: Number(targetTemp) }),
    run,
    push,
  };

  return { d, lines, clear };
}
