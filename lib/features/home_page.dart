import 'package:flutter/material.dart';

import '../shared/widgets/app_nav.dart';
import '../shared/widgets/confirm_dialog.dart';
import 'assistant/pages/assistant_page.dart';
import 'assistant/services/assistant_store.dart';
import 'auth/services/auth.dart';
import 'documents/pages/documents_page.dart';
import 'documents/services/documents_store.dart';
import 'purchases/pages/purchases_page.dart';
import 'purchases/services/plan_store.dart';
import 'settings/pages/settings_page.dart';
import 'umag/services/umag_store.dart';

/// Что показано после входа: раздел выбирают в нижней панели.
///
/// Разделы не складываются в стопку навигации, а подменяют друг друга: они
/// равноправны, и «назад» из закупок должно уводить из приложения, а не в
/// документы. Панель одна на все — она и живёт здесь, снаружи страниц, а
/// страница со своей шапкой и кнопками ложится в тело.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.auth,
    required this.documents,
    required this.plans,
    required this.chat,
    required this.umag,
  });

  final Auth auth;
  final DocumentsStore documents;
  final PlanStore plans;
  final AssistantStore chat;
  final UmagAccountStore umag;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Section _section = Section.documents;

  /// Разделы, открытые этому человеку.
  ///
  /// Закупки и помощник менеджеру закрыты: он принимает товар, а не считает
  /// закуп и не спрашивает аналитику. Кому нужны — доступ выдают руками в
  /// админке, и сервер говорит об этом в `/auth/me/`. Правило считаем не по
  /// роли: оно целиком на той стороне, а здесь только ответ.
  List<Section> get _sections {
    final user = widget.auth.user;

    return [
      Section.documents,
      if (user?.usesPurchases ?? false) Section.purchases,
      if (user?.usesAssistant ?? false) Section.assistant,
      Section.settings,
    ];
  }

  /// Уходим в другой раздел.
  ///
  /// Пока считается план закупа, спрашиваем: расчёт идёт минуту, ходит в
  /// кабинет за товарным отчётом и обрывается вместе с уходом — вернувшись,
  /// человек нашёл бы пустой раздел и начал заново.
  Future<void> _select(Section section) async {
    if (_section == Section.purchases && widget.plans.isCounting) {
      final agreed = await confirm(
        context,
        title: 'Прервать расчёт?',
        message: 'Закуп ещё считается. Уйдёте — придётся считать заново.',
        action: 'Уйти',
        dangerous: true,
      );

      if (!agreed || !mounted) {
        return;
      }
    }

    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    // Под клавиатурой панель прячем. Иначе в «Помощнике» она встаёт полосой
    // между полем ввода и клавиатурой и отъедает у переписки высоту как раз
    // тогда, когда её меньше всего: переключаться между разделами посреди
    // набранного вопроса всё равно никто не станет.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;

    final sections = _sections;

    // Доступ могли отобрать, пока раздел был открыт: возвращаемся к тому, что
    // есть у всех.
    final current = sections.contains(_section) ? _section : Section.documents;

    return Scaffold(
      body: switch (current) {
        Section.documents => DocumentsPage(
          store: widget.documents,
          umag: widget.umag,
        ),
        Section.purchases => PurchasesPage(store: widget.plans),
        Section.assistant => AssistantPage(store: widget.chat),
        Section.settings => SettingsPage(auth: widget.auth, umag: widget.umag),
      },
      bottomNavigationBar: typing
          ? null
          : AppBottomBar(
              sections: sections,
              current: current,
              onSelect: _select,
            ),
    );
  }
}
