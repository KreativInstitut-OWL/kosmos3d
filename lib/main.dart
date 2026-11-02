import 'l10n/app_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/main_menu.dart';
import 'providers/settings_provider.dart';
import 'services/gopro_service.dart';
import 'services/project_service.dart';
import 'services/trajectory_service.dart';
import 'services/upload_service.dart';
import 'services/cloud_storage_service.dart';
import 'services/orientation_service.dart';
import 'services/rig_geometry_service.dart';
import 'services/lidar_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The phone is mounted on the rig in portrait; landscape hid half the UI.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => GoProService()),
        ChangeNotifierProvider(create: (_) => ProjectService()),
        ChangeNotifierProvider(create: (_) => OrientationService()),
        ChangeNotifierProvider(create: (_) => TrajectoryService()),
        ChangeNotifierProvider(create: (_) => UploadService()),
        ChangeNotifierProvider(create: (_) => CloudStorageService()),
        ChangeNotifierProvider(create: (_) => RigGeometryService()),
        ChangeNotifierProvider(
          create: (_) => LidarService()..checkAvailability(),
        ),
      ],
      child: const KosmosApp(),
    ),
  );
}

class KosmosApp extends StatelessWidget {
  const KosmosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'KOSMOS 3D',
          locale: Locale(settings.currentLanguage),
          supportedLocales: const [Locale('en'), Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // Follow user preference (system/dark/light)
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: settings.themeMode,
          home: const _StartupWrapper(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

/// Wraps the main menu to show first-launch setup guide
class _StartupWrapper extends StatefulWidget {
  const _StartupWrapper();

  @override
  State<_StartupWrapper> createState() => _StartupWrapperState();
}

class _StartupWrapperState extends State<_StartupWrapper> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstLaunch());
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenSetup = prefs.getBool('has_seen_setup') ?? false;
    if (!hasSeenSetup && mounted) {
      _showSetupGuide();
      await prefs.setBool('has_seen_setup', true);
    }
  }

  void _showSetupGuide() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        final mutedColor = isDark ? Colors.white70 : Colors.black54;

        return AlertDialog(
          backgroundColor: bgColor,
          title: Column(
            children: [
              const AppText('🌌', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 8),
              AppText(
                'Welcome to KOSMOS 3D',
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _setupStep(
                  Icons.phone_android,
                  'Mount your phone',
                  'Attach your phone to the rig\'s phone mount for accurate sensor tracking (gyroscope, GPS, compass).',
                  textColor,
                  mutedColor,
                ),
                const SizedBox(height: 14),
                _setupStep(
                  Icons.bluetooth,
                  'Power on GoPros',
                  'Turn on all GoPro cameras and make sure Wireless Connections are enabled in each camera\'s settings.',
                  textColor,
                  mutedColor,
                ),
                const SizedBox(height: 14),
                _setupStep(
                  Icons.search,
                  'Scan & Connect',
                  'Go to Device Manager → tap "Scan" → tap each camera to connect. No system Bluetooth pairing needed — the app handles everything!',
                  textColor,
                  mutedColor,
                ),
                const SizedBox(height: 14),
                _setupStep(
                  Icons.cloud,
                  'Storage server (optional)',
                  'Settings → Storage server: connect your own S3-compatible bucket (Backblaze, AWS, Wasabi, R2, MinIO) or the KOSMOS Windows receiver.',
                  textColor,
                  mutedColor,
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const AppText('Got it — Let\'s Go!'),
            ),
          ],
        );
      },
    );
  }

  Widget _setupStep(
    IconData icon,
    String title,
    String desc,
    Color textColor,
    Color mutedColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: AppTheme.neonGreen),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                title,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              AppText(desc, style: TextStyle(color: mutedColor, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => const MainMenuScreen();
}
