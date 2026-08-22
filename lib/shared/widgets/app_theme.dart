import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Свой цвет приложения — тот же, что в веб-кабинете: там это `sky-500`, и
/// одно действие не должно быть в двух местах разного цвета.
///
/// Оттенка два. Тёмный достаётся мелкому — подчёркиванию вкладки, подписи
/// открытого раздела: на белом фоне светлый читается плохо. Крупному вроде
/// кнопок достаётся яркий.
const Color accent = Color(0xFF0EA5E9);
const Color accentDark = Color(0xFF0284C7);

/// Бледный оттенок того же цвета — подложка под выбранным разделом меню.
const Color accentPale = Color(0xFFF0F9FF);

/// Оформление под веб-кабинет: белая шапка, нейтральный фон, скруглений мало.
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    primary: accent,
    surface: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFFAFAFA),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF171717),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // Черта под панелью обязательна: она белая, а под ней белые же вкладки
      // и карточки. Без неё непонятно, где кончается шапка.
      shape: Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
      // Панель светлая — значит часы и батарея наверху должны стать тёмными,
      // иначе на светлом фоне их не видно.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
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
