import { Stack } from 'expo-router';

export default function UpdateStatusLayout() {
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="[taskId]" />
    </Stack>
  );
}