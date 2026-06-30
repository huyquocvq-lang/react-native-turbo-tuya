import { useCallback, useState, type ReactNode } from 'react';
import {
  View,
  Text,
  TextInput,
  Pressable,
  ScrollView,
  StyleSheet,
} from 'react-native';
import { TuyaErrors } from '@jimmy-vu/react-native-turbo-tuya';

// ---------- Console ----------
export type LogKind = 'in' | 'ok' | 'err' | 'evt';
export type LogLine = { id: number; tag: string; text: string; kind: LogKind };

let _seq = 0;

export function useConsole() {
  const [lines, setLines] = useState<LogLine[]>([]);
  const push = useCallback((tag: string, text: string, kind: LogKind = 'in') => {
    setLines((prev) => [{ id: ++_seq, tag, text, kind }, ...prev].slice(0, 200));
  }, []);
  const clear = useCallback(() => setLines([]), []);
  return { lines, push, clear };
}

// Pretty-print any result for the log (objects → compact JSON, truncated).
export function fmt(v: unknown): string {
  if (v === undefined || v === null) return 'ok (void)';
  if (typeof v === 'string') return v.length ? v : '""';
  try {
    const s = JSON.stringify(v);
    return s.length > 500 ? `${s.slice(0, 500)}…` : s;
  } catch {
    return String(v);
  }
}

// Reject shape is { code, message, domain }; classify with TuyaErrors for a human hint.
export function errText(e: any): string {
  const code = e?.code ?? e?.userInfo?.code ?? '';
  const base = e?.message ?? String(e);
  const hint = code !== '' ? `  ·  ${TuyaErrors.describe(code)}` : '';
  return `${base}${hint}`;
}

type Push = (tag: string, text: string, kind?: LogKind) => void;

// Wrap an async lib call: log "calling…" → result (and capture it) or classified error.
export function useRun(push: Push) {
  return useCallback(
    <T,>(label: string, fn: () => Promise<T>, onResult?: (r: T) => void) =>
      async () => {
        push(label, 'calling…', 'in');
        try {
          const r = await fn();
          onResult?.(r);
          push(label, fmt(r), 'ok');
        } catch (e) {
          push(label, errText(e), 'err');
        }
      },
    [push]
  );
}

// ---------- Primitives ----------
export function Section({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
}) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>{title}</Text>
      {subtitle ? <Text style={styles.sectionSub}>{subtitle}</Text> : null}
      <View style={styles.row}>{children}</View>
    </View>
  );
}

export function Field({
  label,
  value,
  onChangeText,
  placeholder,
  numeric,
  secure,
  width = 150,
}: {
  label: string;
  value: string;
  onChangeText: (t: string) => void;
  placeholder?: string;
  numeric?: boolean;
  secure?: boolean;
  width?: number;
}) {
  return (
    <View style={[styles.field, { width }]}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <TextInput
        style={styles.input}
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor="#9aa"
        autoCapitalize="none"
        autoCorrect={false}
        secureTextEntry={secure}
        keyboardType={numeric ? 'numeric' : 'default'}
      />
    </View>
  );
}

export function Btn({
  title,
  onPress,
  kind = 'primary',
}: {
  title: string;
  onPress: () => void;
  kind?: 'primary' | 'ghost' | 'warn';
}) {
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.btn,
        kind === 'ghost' && styles.btnGhost,
        kind === 'warn' && styles.btnWarn,
        pressed && styles.btnPressed,
      ]}
    >
      <Text style={[styles.btnText, kind === 'ghost' && styles.btnTextGhost]}>
        {title}
      </Text>
    </Pressable>
  );
}

export function Console({
  lines,
  onClear,
}: {
  lines: LogLine[];
  onClear: () => void;
}) {
  return (
    <View style={styles.console}>
      <View style={styles.consoleHead}>
        <Text style={styles.consoleTitle}>Console ({lines.length})</Text>
        <Btn title="Clear" onPress={onClear} kind="ghost" />
      </View>
      <ScrollView style={styles.consoleBody}>
        {lines.map((l) => (
          <Text key={l.id} style={[styles.logLine, COLOR[l.kind]]}>
            {PREFIX[l.kind]} {l.tag}: {l.text}
          </Text>
        ))}
        {lines.length === 0 ? (
          <Text style={styles.logMuted}>No output yet — tap an action above.</Text>
        ) : null}
      </ScrollView>
    </View>
  );
}

const PREFIX: Record<LogKind, string> = { in: '▶', ok: '✓', err: '✗', evt: '◆' };
const COLOR: Record<LogKind, object> = {
  in: { color: '#9aa' },
  ok: { color: '#3fbf6f' },
  err: { color: '#ff6b6b' },
  evt: { color: '#5aa9ff' },
};

const styles = StyleSheet.create({
  section: { marginBottom: 14 },
  sectionTitle: { fontSize: 15, fontWeight: '700', color: '#16324f' },
  sectionSub: { fontSize: 11, color: '#7a8', marginBottom: 6 },
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, alignItems: 'flex-end' },
  field: { gap: 2 },
  fieldLabel: { fontSize: 11, color: '#567' },
  input: {
    borderWidth: 1,
    borderColor: '#cdd',
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 6,
    color: '#123',
    backgroundColor: '#fff',
  },
  btn: {
    backgroundColor: '#1f6feb',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  btnGhost: { backgroundColor: 'transparent', borderWidth: 1, borderColor: '#cdd' },
  btnWarn: { backgroundColor: '#d1453b' },
  btnPressed: { opacity: 0.6 },
  btnText: { color: '#fff', fontWeight: '600', fontSize: 13 },
  btnTextGhost: { color: '#456' },
  console: {
    marginTop: 8,
    borderTopWidth: 1,
    borderTopColor: '#234',
    backgroundColor: '#0d1117',
    borderRadius: 10,
    overflow: 'hidden',
  },
  consoleHead: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 6,
    backgroundColor: '#161b22',
  },
  consoleTitle: { color: '#c9d1d9', fontWeight: '700' },
  consoleBody: { maxHeight: 260, padding: 10 },
  logLine: { fontFamily: 'Courier', fontSize: 11, marginBottom: 3 },
  logMuted: { color: '#566', fontStyle: 'italic', fontSize: 12 },
});
