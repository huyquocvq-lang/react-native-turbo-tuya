import { useState } from 'react';
import { Text, View, StyleSheet, Button } from 'react-native';
import { Tuya } from '@jimmy-vu/react-native-turbo-tuya';

// LƯU Ý: example này cần native build (B3–B5) thì initSdk mới chạy.
// Trước đó nút sẽ báo lỗi "module not implemented" — đúng như mong đợi.
export default function App() {
  const [status, setStatus] = useState('idle');

  return (
    <View style={styles.container}>
      <Text>Tuya SDK: {status}</Text>
      <Button
        title="Init SDK"
        onPress={async () => {
          try {
            const ok = await Tuya.initSdk();
            setStatus(ok ? 'initialized' : 'init returned false');
          } catch (e) {
            setStatus(`error: ${String(e)}`);
          }
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
  },
});
