import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Бирюзовый — цвет приложения: им красится верхняя панель и кнопки.
///
/// Оттенка два, и это не случайность. Панель темнее: на ней лежит мелкий текст
/// вроде названия организации, и на светлой бирюзе белые буквы читались бы
/// плохо. Кнопкам мелкий текст не грозит, поэтому им достаётся яркий.
const Color turquoise = Color(0xFF0D9488);
const Color turquoiseDark = Color(0xFF0F766E);

/// Оформление под веб-кабинет: нейтральный фон, бирюзовый акцент, скруглений мало.
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: turquoise,
    primary: turquoise,
    surface: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFFAFAFA),
    appBarTheme: const AppBarTheme(
      toolbarHeight: 72,
      backgroundColor: turquoiseDark,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // Панель тёмная — значит часы и батарея наверху должны стать светлыми,
      // иначе на iOS они сольются с фоном.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFFD4D4D4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Color(0xFFD4D4D4)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
  );
}
