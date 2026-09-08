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

  @override
  void initState() {
    super.initState();
    widget.documents.addListener(_onChanged);
    // От него зависит, есть ли «Документы» в панели: без запроса раздел
    // появился бы у всех, хотя расширение ещё не подключали.
    widget.documents.load();
  }

  @override
  void dispose() {
    widget.documents.removeListener(_onChanged);
    super.dispose();
  }

  /// Разделы, открытые этому человеку.
  ///
  /// Документы — это расширение: без подключения раздела в панели нет, как
  /// у закупок. Закупки и помощник менеджеру закрыты, пока доступ не выдали
  /// руками в админке. Правило считаем не по роли: оно целиком на сервере,
  /// а здесь только ответ `/auth/me/`.
  List<Section> get _sections {
    final user = widget.auth.user;

    return [
      if (widget.documents.isConnected || widget.documents.connectionUnknown)
        Section.documents,
      if (user?.usesPurchases ?? false) Section.purchases,
      if (user?.usesAssistant ?? false) Section.assistant,
      Section.settings,
    ];
  }

  void _onChanged() {
    // Список документов сам себя перечитывает в `initState` — уведомление
    // приходит, пока HomePage ещё строится. `setState` откладываем на кадр.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
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
    // ещё есть в панели. Настройки есть всегда.
    final current = sections.contains(_section) ? _section : sections.first;

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
      bottomNavigationBar: typing || sections.length < 2
          ? null
          : AppBottomBar(
              sections: sections,
              current: current,
              onSelect: _select,
            ),
    );
  }
}
