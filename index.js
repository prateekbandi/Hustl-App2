// 1) MUST be first for iOS native modules
import 'react-native-gesture-handler';
// 2) Reanimated must load before app code
import 'react-native-reanimated';
// 3) Hand off to Expo Router
import 'expo-router/entry';