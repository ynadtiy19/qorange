import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF006D77); // 柔和的深青色
  static const Color secondary = Color(0xFF83C5BE);
  static const Color background = Color(0xFFEDF6F9); // 平静的暖沙色
  static const Color textDark = Color(0xFF2B2D42);
  static const Color textLight = Color(0xFF8D99AE);
  static const Color userBubble = Color(0xFF006D77);
  static const Color aiBubble = Color(0xFFFFFFFF);

  static ThemeData get theme => ThemeData(
        scaffoldBackgroundColor: background,
        primaryColor: primary,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          elevation: 0,
          iconTheme: IconThemeData(color: textDark),
          titleTextStyle: TextStyle(
            color: textDark,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          centerTitle: true,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      );
}
