import { createClient } from '@supabase/supabase-js';
import 'react-native-url-polyfill/auto';

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

// Validate required environment variables
if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Missing Supabase configuration. Please set EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY in your .env file. ' +
    'Get these values from: https://app.supabase.com/project/YOUR_PROJECT/settings/api'
  );
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    // Disable automatic session refresh for better mobile performance
    autoRefreshToken: true,
    // Persist session in AsyncStorage for mobile
    persistSession: true,
    // Detect session from URL for web compatibility
    detectSessionInUrl: false,
  },
});

export default supabase;