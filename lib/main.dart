import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'screens/splash_screen.dart';
import 'storage.dart';
import 'store/store_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status bar and the camera cutout (the editor handles safe areas itself).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await StoreService.instance.init();
  runApp(const KainuwaStudioApp());
}

class KainuwaStudioApp extends StatefulWidget {
  const KainuwaStudioApp({super.key});

  @override
  State<KainuwaStudioApp> createState() => _KainuwaStudioAppState();
}

class _KainuwaStudioAppState extends State<KainuwaStudioApp> {
  late final AppState _state = AppState(StorageService());

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'Qur\'an Studio',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (context, child) {
          // Phones set to very large text would otherwise break the layout.
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
