import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'services/auth_service.dart';
import 'services/subscription_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/store_setup_screen.dart';
import 'screens/subscription_wall_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  // Determine start screen
  Widget startScreen;

  final hasSession = await AuthService.restoreSession();

  if (!hasSession) {
    startScreen = const LoginScreen();
  } else if (AuthService.storeId == null) {
    startScreen = const StoreSetupScreen();
  } else {
    final sub = await SubscriptionService.check();
    startScreen = SubscriptionService.isActive
        ? const HomeScreen()
        : const SubscriptionWallScreen();
  }

  runApp(MobileStoreApp(startScreen: startScreen));
}

class MobileStoreApp extends StatelessWidget {
  final Widget startScreen;
  const MobileStoreApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Store',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1976D2),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          filled: true,
        ),
      ),
      home: startScreen,
    );
  }
}
