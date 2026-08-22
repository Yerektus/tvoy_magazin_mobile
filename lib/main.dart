import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/auth/pages/login_page.dart';
import 'features/auth/services/auth.dart';
import 'features/documents/pages/documents_page.dart';
import 'features/documents/services/documents_store.dart';
import 'features/umag/services/umag_store.dart';
import 'shared/services/api_client.dart';
import 'shared/widgets/app_theme.dart';

void main() {
  final api = ApiClient();

  runApp(
    App(
      auth: Auth(api: api),
      store: DocumentsStore(api: api),
      umag: UmagAccountStore(api: api),
    ),
  );
}

/// Точка сборки: держит службы и решает, какой экран показать.
///
/// Роутера тут нет намеренно — экрана всего два, и выбор между ними целиком
/// определяется тем, есть ли вход. Появится третий — придёт и Navigator.
class App extends StatefulWidget {
  const App({
    super.key,
    required this.auth,
    required this.store,
    required this.umag,
  });

  final Auth auth;
  final DocumentsStore store;
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

    return DocumentsPage(
      auth: widget.auth,
      store: widget.store,
      umag: widget.umag,
    );
  }
}
