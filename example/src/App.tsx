import { useState } from 'react';
import { SafeAreaView, ScrollView, Text, View, Pressable, StyleSheet } from 'react-native';
import { Console } from './ui';
import { useDemo } from './useDemo';
import { HappyPath } from './HappyPath';
import {
  CoreSection,
  AuthSection,
  HomeSection,
  PairingSection,
  DeviceSection,
  AdvancedSection,
} from './sections';

// Demo app for @jimmy-vu/react-native-turbo-tuya.
// Two tabs: "Explorer" (every API, one section per module) + "Happy path" (auto sequential ice-bath flow).
// Shared inputs + live event log + TuyaErrors classification live in useDemo().
// NOTE: requires a real native build (JDK17+Android SDK / macOS+Xcode + valid AppKey/Secret).
type Tab = 'explorer' | 'happy';

export default function App() {
  const { d, lines, clear } = useDemo();
  const [tab, setTab] = useState<Tab>('explorer');

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.header}>
        <Text style={styles.h1}>react-native-turbo-tuya</Text>
        <Text style={styles.h2}>Full SDK demo · 12 TurboModules</Text>
        <View style={styles.tabs}>
          <TabBtn label="Explorer" active={tab === 'explorer'} onPress={() => setTab('explorer')} />
          <TabBtn label="Happy path" active={tab === 'happy'} onPress={() => setTab('happy')} />
        </View>
      </View>

      <ScrollView contentContainerStyle={styles.scroll}>
        {tab === 'explorer' ? (
          <>
            <CoreSection d={d} />
            <AuthSection d={d} />
            <HomeSection d={d} />
            <PairingSection d={d} />
            <DeviceSection d={d} />
            <AdvancedSection d={d} />
          </>
        ) : (
          <HappyPath d={d} />
        )}

        <Console lines={lines} onClear={clear} />
      </ScrollView>
    </SafeAreaView>
  );
}

function TabBtn({
  label,
  active,
  onPress,
}: {
  label: string;
  active: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable onPress={onPress} style={[styles.tab, active && styles.tabActive]}>
      <Text style={[styles.tabText, active && styles.tabTextActive]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f3f6f9' },
  header: { paddingHorizontal: 14, paddingTop: 10 },
  h1: { fontSize: 20, fontWeight: '800', color: '#0d1b2a' },
  h2: { fontSize: 12, color: '#5a7', marginBottom: 8 },
  tabs: { flexDirection: 'row', gap: 8, marginBottom: 4 },
  tab: {
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#cdd',
  },
  tabActive: { backgroundColor: '#1f6feb', borderColor: '#1f6feb' },
  tabText: { color: '#456', fontWeight: '600', fontSize: 13 },
  tabTextActive: { color: '#fff' },
  scroll: { padding: 14, paddingBottom: 40 },
});
