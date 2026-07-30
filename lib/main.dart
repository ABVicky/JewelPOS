import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'android_ui.dart';
import 'server_helper.dart';
import 'windows_ui.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DesktopHttpServer.startServer();
  }

  runApp(const JewelPOSApp());
}

class JewelPOSApp extends StatelessWidget {
  const JewelPOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    Widget activeHome;

    if (defaultTargetPlatform == TargetPlatform.android) {
      activeHome = const AndroidHandPOSApp();
    } else {
      activeHome = const WindowsInventoryApp();
    }

    return MaterialApp(
      title: 'Jewel POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        primaryColor: const Color(0xFF1E293B),
        scaffoldBackgroundColor: const Color(0xFFE2E8F0),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1E293B),
          secondary: Color(0xFF0F172A),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Color(0xFF0F172A), width: 2),
          ),
        ),
      ),
      home: activeHome,
    );
  }
}
