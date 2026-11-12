import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get cyberpunkRed {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF050505), // Negro profundo
      primaryColor: const Color(0xFFFF003C), // Rojo neón agresivo
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFF003C),
        secondary: Color(0xFF8A0021), // Rojo sangre oscuro
        surface: Color(0xFF121212), // Fondo de tarjetas
      ),
      fontFamily: 'Courier', // Cambia a 'Rajdhani' o 'Share Tech Mono' si usas Google Fonts
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF050505),
        elevation: 0.0, // <-- CORREGIDO: 0 a 0.0
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Color(0xFFFF003C),
          fontSize: 22.0, // <-- CORREGIDO: 22 a 22.0
          fontWeight: FontWeight.bold,
          letterSpacing: 3.0,
        ),
      ),
    );
  }
}