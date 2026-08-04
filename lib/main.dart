import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'UI.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // فحص ما إذا كانت هذه هي المرة الأولى التي يفتح فيها المستخدم التطبيق
  final prefs = await SharedPreferences.getInstance();
  final bool isFirstRun = prefs.getBool('is_first_run') ?? true;

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.nova.media.channel.audio',
    androidNotificationChannelName: 'Nova Media Playback',
    androidNotificationOngoing: true,
    androidNotificationIcon: 'mipmap/ic_launcher',
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0F0F1E),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('ar', ''), Locale('en', '')],
      path: 'assets/translations',
      fallbackLocale: const Locale('ar', ''),
      child: OfflineMediaPlayerApp(isFirstRun: isFirstRun),
    ),
  );
}

// ====================================================================
// Root Application
// ====================================================================
class OfflineMediaPlayerApp extends StatelessWidget {
  final bool isFirstRun;
  const OfflineMediaPlayerApp({super.key, required this.isFirstRun});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nova Media',
      debugShowCheckedModeBanner: false,

      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,

      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F1E),
        primaryColor: const Color(0xFF6C5CE7),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C5CE7),
          surface: Color(0xFF1E1E2C),
        ),
      ),

      // إذا كانت المرة الأولى، يظهر شاشة اختيار اللغة، وإلا تفتح الشاشة الرئيسية مباشرة
      home: isFirstRun ? const FirstRunLanguageScreen() : const MainScreenUI(),
    );
  }
}

// ====================================================================
// شاشة اختيار اللغة لأول مرة (تظهر مرة واحدة فقط)
// ====================================================================
class FirstRunLanguageScreen extends StatelessWidget {
  const FirstRunLanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.language_rounded, size: 80, color: Color(0xFF00BCD4)),
              const SizedBox(height: 24),
              const Text(
                'Welcome to Nova Media\nأهلاً بك في نوفا ميديا',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please select your preferred language\nيرجى اختيار لغة التطبيق المفضلة لديك',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 48),

              // زر اللغة العربية
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E1E2C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFF00BCD4), width: 1.5),
                    ),
                  ),
                  onPressed: () async {
                    context.setLocale(const Locale('ar', ''));
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('is_first_run', false);

                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (c) => const MainScreenUI()),
                      );
                    }
                  },
                  child: const Text(
                    'العربية',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // زر اللغة الإنجليزية
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E1E2C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFF00BCD4), width: 1.5),
                    ),
                  ),
                  onPressed: () async {
                    context.setLocale(const Locale('en', ''));
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('is_first_run', false);

                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (c) => const MainScreenUI()),
                      );
                    }
                  },
                  child: const Text(
                    'English',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}