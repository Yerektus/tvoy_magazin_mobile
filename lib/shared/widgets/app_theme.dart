import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Свой цвет приложения — тот же, что в веб-кабинете: там это `blue-500`, и
/// одно действие не должно быть в двух местах разного цвета.
///
/// Оттенка два. Тёмный достаётся мелкому — подчёркиванию вкладки, подписи
/// открытого раздела: на белом фоне светлый читается плохо. Крупному вроде
/// кнопок достаётся яркий.
const Color accent = Color(0xFF3B82F6);
const Color accentDark = Color(0xFF2563EB);

/// Бледный оттенок того же цвета — подложка под выбранным разделом меню.
const Color accentPale = Color(0xFFEFF6FF);

/// Цвет помощника. В кабинете это `violet-500` у искры в шапке — то же
/// действие не должно быть синим, как обычные кнопки кабинета.
const Color assistantAccent = Color(0xFF8B5CF6);

/// Высота шапки. Выше стандартных 56: заголовок и кнопка действия стоят в один
/// ряд, и на тесной полосе они жались друг к другу.
const double appBarHeight = 64;

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
    // Inter — как в веб-кабинете. Системный шрифт на айфоне и на андроиде
    // разный, и одни и те же экраны выглядели по-разному на двух телефонах.
    fontFamily: 'Inter',
    scaffoldBackgroundColor: const Color(0xFFFAFAFA),
    // Назад — тонким шевроном, а не стрелкой: он легче и не спорит с иконками
    // действий справа, которые у нас той же линейной рисовки.
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) =>
          const Icon(LucideIcons.chevron_left, size: 26),
    ),
    appBarTheme: const AppBarTheme(
      toolbarHeight: appBarHeight,
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
