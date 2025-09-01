import { ConfigContext, ExpoConfig } from "expo/config";

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: "bolt-expo-nativewind",
  slug: "bolt-expo-nativewind",
  version: "1.0.0",
  orientation: "portrait",
  icon: "./src/assets/images/icon.png",
  scheme: "myapp",
  userInterfaceStyle: "automatic",
  newArchEnabled: true,

  ios: {
    supportsTablet: true,
    bundleIdentifier: "com.hustl.app",
    infoPlist: {
      NSLocationWhenInUseUsageDescription:
        "We use your location to show nearby tasks on the map.",
      LSApplicationQueriesSchemes: ["comgooglemaps"]
    }
  },

  android: {
    package: "com.hustl.app"
  },

  web: {
    bundler: "metro",
    output: "single",
    favicon: "./src/assets/images/favicon.png"
  },

  plugins: [
    "expo-router",
    // Put your key in an env var in real projects
    ["expo-maps", { googleMapsApiKey: process.env.EXPO_PUBLIC_GOOGLE_MAPS_API_KEY || "YOUR_MAPS_KEY" }],
    ["expo-location", {
      locationAlwaysAndWhenInUseUsageDescription:
        "We use your location to show nearby tasks on the map."
    }],
    "expo-dev-client"
  ],

  experiments: {
    typedRoutes: true
  },

  extra: {
    EXPO_PUBLIC_GOOGLE_MAPS_API_KEY: process.env.EXPO_PUBLIC_GOOGLE_MAPS_API_KEY
  }
});
