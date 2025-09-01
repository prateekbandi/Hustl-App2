// This must be FIRST for iOS to avoid native crashes
import 'react-native-gesture-handler';
// Reanimated can safely load after GH
import 'react-native-reanimated';
// Hand off to Expo Router
import 'expo-router/entry';