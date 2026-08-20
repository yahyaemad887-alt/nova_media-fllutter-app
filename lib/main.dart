// ====================================================================
// MAIN ENTRY POINT - NOVA MEDIA APPLICATION (LARK PLAYER ENGINE)
// ====================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'SERVICES.dart';
import 'audio_player_handler.dart';
import 'UI.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  bool isFirstRun = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    isFirstRun = prefs.getBool('is_first_run') ?? true;
  } catch (e) {
    debugPrint('Error reading SharedPreferences: $e');
  }

  try {
    await initAudioServiceHandler(); // التعديل الصح هنا
  } catch (e) {
    debugPrint('Error initializing AudioService: $e');
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF0F0F1E),
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('ar', ''), Locale('en', '')],
      path: 'assets/translations',
      fallbackLocale: const Locale('ar', ''),
      saveLocale: true,
      child: OfflineMediaPlayerApp(isFirstRun: isFirstRun),
    ),
  );
}

// ====================================================================
// Root Application Widget
// ====================================================================
class OfflineMediaPlayerApp extends StatelessWidget {
  final bool isFirstRun;

  const OfflineMediaPlayerApp({super.key, required this.isFirstRun});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'app_name'.tr(),
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
          secondary: Color(0xFF00BCD4),
          surface: Color(0xFF1E1E2C),
          onSurface: Colors.white,
        ),
        fontFamily: 'Cairo',
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),

      home: isFirstRun ? const FirstRunLanguageScreen() : const MainScreenUI(),
    );
  }
}

// ====================================================================
// شاشة اختيار اللغة لأول مرة
// ====================================================================
class FirstRunLanguageScreen extends StatelessWidget {
  const FirstRunLanguageScreen({super.key});

  Future<void> _selectLanguage(BuildContext context, Locale locale) async {
    HapticFeedback.mediumImpact();

    await context.setLocale(locale);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_first_run', false);
    } catch (e) {
      debugPrint('Error saving first_run status: $e');
    }

    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: const MainScreenUI(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.language_rounded,
                  size: 72,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 32),

              Text(
                'welcome_title'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),

              Text(
                'select_language_subtitle'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),

              const Spacer(),

              LanguageOptionButton(
                title: 'lang_ar_title'.tr(),
                subtitle: 'Arabic',
                icon: '🇸🇦',
                onPressed: () => _selectLanguage(context, const Locale('ar', '')),
              ),
              const SizedBox(height: 16),

              LanguageOptionButton(
                title: 'lang_en_title'.tr(),
                subtitle: 'الإنجليزية',
                icon: '🇺🇸',
                onPressed: () => _selectLanguage(context, const Locale('en', '')),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================================================================
// Reusable Component: Language Option Button
// ====================================================================
class LanguageOptionButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final String icon;
  final VoidCallback onPressed;

  const LanguageOptionButton({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E1E2C),
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF00BCD4), width: 1.2),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          children: [
            Text(
              icon,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}