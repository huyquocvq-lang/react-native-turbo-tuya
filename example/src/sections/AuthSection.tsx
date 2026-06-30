import { Tuya } from '@jimmy-vu/react-native-turbo-tuya';
import { Section, Field, Btn } from '../ui';
import type { DemoCtx } from '../useDemo';

export function AuthSection({ d }: { d: DemoCtx }) {
  return (
    <Section title="2 · Auth" subtitle="email login/register + session (type: 1=register, 2=login)">
      <Field label="Country" value={d.countryCode} onChangeText={d.setCountryCode} width={80} numeric />
      <Field label="Email" value={d.email} onChangeText={d.setEmail} width={200} placeholder="you@mail.com" />
      <Field label="Password" value={d.password} onChangeText={d.setPassword} secure />
      <Field label="OTP code" value={d.code} onChangeText={d.setCode} width={100} numeric />
      <Btn title="Send code (register)" onPress={d.run('sendVerifyCode', () => Tuya.sendVerifyCode(d.email, d.countryCode, 1))} kind="ghost" />
      <Btn title="Send code (login)" onPress={d.run('sendVerifyCode', () => Tuya.sendVerifyCode(d.email, d.countryCode, 2))} kind="ghost" />
      <Btn title="Register" onPress={d.run('registerWithEmail', () => Tuya.registerWithEmail(d.countryCode, d.email, d.password, d.code))} />
      <Btn title="Login (password)" onPress={d.run('loginWithEmail', () => Tuya.loginWithEmail(d.countryCode, d.email, d.password))} />
      <Btn title="Login (code)" onPress={d.run('loginWithEmailCode', () => Tuya.loginWithEmailCode(d.countryCode, d.email, d.code))} />
      <Btn title="Is logged in?" onPress={d.run('isLoggedIn', () => Tuya.isLoggedIn())} kind="ghost" />
      <Btn title="Current user" onPress={d.run('getCurrentUser', () => Tuya.getCurrentUser())} kind="ghost" />
      <Btn title="Logout" onPress={d.run('logout', () => Tuya.logout())} kind="warn" />
    </Section>
  );
}
