import 'package:flutter/material.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../services/auth.dart';

/// Вход по почте и паролю. Заходят в организацию: учётку без неё сервер не
/// пускает и говорит об этом текстом ошибки — его показываем окном.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.auth});

  final Auth auth;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _hidden = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) {
      return;
    }

    setState(() => _busy = true);

    try {
      await widget.auth.signIn(_email.text, _password.text);
      // Дальше решает `App`: он слушает Auth и сам покажет список документов.
    } on ApiException catch (error) {
      if (mounted) {
        // Клавиатура закрывает низ экрана — убираем её, иначе окно окажется
        // над ней и прочитать сообщение будет негде.
        FocusScope.of(context).unfocus();
        await showErrorDialog(context, message: error.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Добро пожаловать!',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Заполните данные для входа в систему',
                      style: TextStyle(color: Color(0xFF737373)),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _email,
                      autocorrect: false,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Почта'),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty ? 'Введите почту' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidden,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _hidden = !_hidden),
                          icon: Icon(
                            _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          ),
                          tooltip: _hidden ? 'Показать пароль' : 'Скрыть пароль',
                        ),
                      ),
                      validator: (value) =>
                          (value ?? '').isEmpty ? 'Введите пароль' : null,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Войти'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
