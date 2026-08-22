import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/auth/pages/login_page.dart';
import 'features/auth/services/auth.dart';
import 'features/documents/services/documents_store.dart';
import 'features/home_page.dart';
import 'features/purchases/services/plan_store.dart';
import 'features/umag/services/umag_store.dart';
import 'shared/services/api_client.dart';
import 'shared/widgets/app_theme.dart';

void main() {
  final api = ApiClient();

  runApp(
    App(
      auth: Auth(api: api),
      store: DocumentsStore(api: api),
      plans: PlanStore(api: api),
      umag: UmagAccountStore(api: api),
    ),
  );
}

/// Точка сборки: держит службы и решает, показывать вход или приложение.
///
/// Роутера тут нет намеренно: снаружи выбор один — вошли или нет. Разделы
/// внутри приложения переключает [HomePage], и стопки навигации им не нужно —
/// они равноправны.
class App extends StatefulWidget {
  const App({
    super.key,
    required this.auth,
    required this.store,
    required this.plans,
    required this.umag,
  });

  final Auth auth;
  final DocumentsStore store;
  final PlanStore plans;
  final UmagAccountStore umag;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onChanged);
    widget.auth.restore();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Твой магазин',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Свои строки у нас русские, а встроенные Flutter отдавал по-английски:
      // подсказка у кнопки меню читалась как «Open navigation menu». Сюда же
      // попадают названия месяцев, «Отмена» в системных окнах и прочее, чего
      // мы не пишем сами.
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _home(),
    );
  }

  Widget _home() {
    if (widget.auth.isRestoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!widget.auth.isAuthenticated) {
      return LoginPage(auth: widget.auth);
    }

    return HomePage(
      auth: widget.auth,
      documents: widget.store,
      plans: widget.plans,
      umag: widget.umag,
    );
  }
}
