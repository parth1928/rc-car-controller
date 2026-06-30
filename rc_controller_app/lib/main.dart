import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'features/drive/drive_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Force landscape orientation for the controller
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Hide status bar and navigation keys for full immersion
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RC Controller',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      home: const DriveScreen(),
    );
  }
}
