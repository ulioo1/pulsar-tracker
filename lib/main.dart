import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/screens/dashboard_screen.dart';

void main() async {
  // Asegura que los bindings de Flutter estén inicializados antes de llamar a código nativo (Firebase)
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa Firebase usando la configuración generada por FlutterFire CLI
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const PulsarTrackerApp());
}

class PulsarTrackerApp extends StatelessWidget {
  const PulsarTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pulsar N125 Tracker',
      theme: AppTheme.cyberpunkRed,
      home: const DashboardScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}