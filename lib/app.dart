import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

class FutureMeetingNotesApp extends StatelessWidget {
  const FutureMeetingNotesApp({super.key});

  static const _seed = Color(0xFF1F5F6B);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Future Meeting Notes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
      ),
      home: const HomeScreen(),
    );
  }
}
