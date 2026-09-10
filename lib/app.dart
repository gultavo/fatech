import 'package:flutter/material.dart';

import 'screens/visits_screen.dart';
import 'services/app_services.dart';

class FatechApp extends StatelessWidget {
  const FatechApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF153F5F);
    const blue = Color(0xFF1C70AD);
    const green = Color(0xFF279271);
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.light,
    ).copyWith(primary: blue, secondary: green, surface: Colors.white);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FAtech',
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFEDF3F6),
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 1,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blueGrey.shade100),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: VisitsScreen(services: services),
    );
  }
}
