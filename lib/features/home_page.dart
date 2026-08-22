import 'package:flutter/material.dart';

import '../shared/widgets/app_drawer.dart';
import 'auth/services/auth.dart';
import 'documents/pages/documents_page.dart';
import 'documents/services/documents_store.dart';
import 'purchases/pages/purchases_page.dart';
import 'purchases/services/plan_store.dart';
import 'umag/services/umag_store.dart';

/// Что показано после входа: раздел выбирают в боковом меню.
///
/// Разделы не складываются в стопку навигации, а подменяют друг друга: они
/// равноправны, и «назад» из закупок должно уводить из приложения, а не в
/// документы. Меню одно на оба — его и передаём вниз готовым виджетом.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.auth,
    required this.documents,
    required this.plans,
    required this.umag,
  });

  final Auth auth;
  final DocumentsStore documents;
  final PlanStore plans;
  final UmagAccountStore umag;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Section _section = Section.documents;

  @override
  Widget build(BuildContext context) {
    final drawer = AppDrawer(
      auth: widget.auth,
      umag: widget.umag,
      current: _section,
      onSelect: (section) => setState(() => _section = section),
    );

    return switch (_section) {
      Section.documents => DocumentsPage(
        store: widget.documents,
        umag: widget.umag,
        drawer: drawer,
      ),
      Section.purchases => PurchasesPage(store: widget.plans, drawer: drawer),
    };
  }
}
