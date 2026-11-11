import 'package:flutter/material.dart';

/// Tokens de color tomados del Figma. Se definen una sola vez aquí.
class Colores {
  static const primario = Color(0xFF2563EB);
  static const exito = Color(0xFF34D399);
  static const exitoOscuro = Color(0xFF047857);
  static const exitoFondo = Color(0xFFECFDF5);
  static const fondo = Color(0xFFF3F6FB);
  static const texto = Color(0xFF111827);
  static const textoSuave = Color(0xFF6B7280);
  static const borde = Color(0xFFE5E7EB);
  static const filaAlterna = Color(0xFFF8FAFC);
  static const avisoFondo = Color(0xFFFEF3C7);
  static const avisoTexto = Color(0xFF92400E);
  static const peligro = Color(0xFFB91C1C);
  static const peligroFondo = Color(0xFFFEE2E2);
  static const infoFondo = Color(0xFFEFF6FF);
}

class Tema {
  static ThemeData claro() {
    final borde = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colores.borde),
    );
    final forma = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colores.primario,
        primary: Colores.primario,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colores.fondo,
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colores.texto,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: borde,
        enabledBorder: borde,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: forma),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: forma,
          foregroundColor: Colores.texto,
          side: const BorderSide(color: Colores.borde),
          backgroundColor: Colors.white,
        ),
      ),
    );
  }
}
