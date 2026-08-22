import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Встроенные строки Flutter должны быть русскими: подсказку у кнопки меню
/// пишем не мы, а `MaterialLocalizations`, и без делегатов она английская.
void main() {
  testWidgets('встроенные строки приходят по-русски', (tester) async {
    late MaterialLocalizations strings;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            strings = MaterialLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(strings.openAppDrawerTooltip, 'Открыть меню навигации');
    expect(strings.closeButtonTooltip, 'Закрыть');
  });
}
