import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/chasqui_service.dart';
import 'screens/dashboard_screen.dart';
import 'package:flutter/services.dart';
import 'bridge_generated.dart/frb_generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inicializa el núcleo Rust (crypto_core) antes de crear el servicio, que
  // deriva la identidad Ed25519 real a través del puente.
  try {
    await RustLib.init();
  } catch (e) {
    debugPrint('Error al inicializar RustLib: $e');
  }
  // Inicia el Foreground Service en segundo plano sin bloquear el arranque de la UI
  _ensureForegroundService();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ChasquiService(),
      child: const WanadiChasquiApp(),
    ),
  );
}

/// Inicia el servicio Android que mantiene activo el daemon BLE.
Future<void> _ensureForegroundService() async {
  const MethodChannel channel = MethodChannel('com.wanadi.chasqui/foreground');
  try {
    await channel.invokeMethod('startForegroundDaemon');
  } on PlatformException catch (e) {
    // Si el service falla, se registra pero la app sigue funcionando.
    debugPrint('Error al iniciar Foreground Service: ${e.message}');
  }
}

// ─────────────────────────────────────────────────────────────────
//  Paleta de Colores Oficial Wanadi Chasqui (Brand Guide)
// ─────────────────────────────────────────────────────────────────
class WanadiBrand {
  WanadiBrand._();

  // Paleta principal
  static const Color navyDeep = Color(0xFF0A2540);
  static const Color mintTech = Color(0xFF00D9A5);
  static const Color charcoalGrey = Color(0xFF2A2A2A);
  static const Color pureWhite = Color(0xFFFFFFFF);

  // Colores de estado
  static const Color safe = Color(0xFF00D945);
  static const Color warning = Color(0xFFF5B942);
  static const Color error = Color(0xFFE5484D);
  static const Color info = Color(0xFF3B82F6);

  // Superficies derivadas
  static const Color surfaceDark = Color(0xFF0F2D4A); // Cartas sobre navyDeep
  static const Color surfaceLight = Color(0xFFF0F7FA); // Fondo claro
  static const Color divider = Color(0xFF1A3A5C);
}

class WanadiChasquiApp extends StatelessWidget {
  const WanadiChasquiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<ChasquiService>(context);

    return MaterialApp(
      title: 'Wanadi Chasqui',
      debugShowCheckedModeBanner: false,
      themeMode: service.isDarkMode ? ThemeMode.dark : ThemeMode.light,

      // ─── Tema Claro ──────────────────────────────────────────
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: WanadiBrand.surfaceLight,
        colorScheme: const ColorScheme.light(
          primary: WanadiBrand.mintTech,
          secondary: WanadiBrand.navyDeep,
          surface: WanadiBrand.pureWhite,
          error: WanadiBrand.error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: WanadiBrand.pureWhite,
          elevation: 1,
          iconTheme: IconThemeData(color: WanadiBrand.navyDeep),
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: WanadiBrand.navyDeep,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardTheme(
          color: WanadiBrand.pureWhite,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: WanadiBrand.pureWhite,
          selectedItemColor: WanadiBrand.mintTech,
          unselectedItemColor: WanadiBrand.charcoalGrey,
        ),
      ),

      // ─── Tema Oscuro (Principal) ─────────────────────────────
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: WanadiBrand.navyDeep,
        colorScheme: const ColorScheme.dark(
          primary: WanadiBrand.mintTech,
          secondary: WanadiBrand.info,
          surface: WanadiBrand.surfaceDark,
          error: WanadiBrand.error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: WanadiBrand.surfaceDark,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: WanadiBrand.pureWhite,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardTheme(
          color: WanadiBrand.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        dialogTheme: DialogTheme(
          backgroundColor: WanadiBrand.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: WanadiBrand.surfaceDark,
          selectedItemColor: WanadiBrand.mintTech,
          unselectedItemColor: Colors.grey,
        ),
        dividerColor: WanadiBrand.divider,
      ),
      home: const DashboardScreen(),
    );
  }
}
