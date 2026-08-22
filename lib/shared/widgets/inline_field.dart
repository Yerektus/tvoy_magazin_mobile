import 'package:flutter/material.dart';

/// Значение, которое правится прямо в строке.
///
/// Без рамки и подписи, на сером фоне: подпись уже стоит слева, а рамка вокруг
/// каждого поля превратила бы страницу в анкету. Серая заливка — единственное,
/// что отличает правимое от справочного.
///
/// Сохраняет по Enter и по потере фокуса, и только если значение изменилось:
/// иначе каждый случайный тап по полю слал бы запрос.
class InlineField extends StatefulWidget {
  const InlineField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.enabled = true,
  });

  final String value;

  /// Вызывается с новым значением. Дождавшись её, поле сверяется с `value`:
  /// если правка не прижилась — сервер отказал или число не разобралось, — в
  /// поле возвращается то, что действительно сохранено. Так на экране никогда
  /// не остаётся текст, которого нет в базе.
  final Future<void> Function(String) onChanged;

  final String? hint;
  final TextInputType? keyboardType;

  /// `null` — поле растёт по тексту. Длинные названия товаров и поставщиков
  /// иначе обрезаются, а править вслепую то, чего не видно, невозможно.
  final int? maxLines;
  final bool enabled;

  @override
  State<InlineField> createState() => _InlineFieldState();
}

class _InlineFieldState extends State<InlineField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChanged);

  /// Отправка уже идёт. Без этого правка уходила дважды: окно с ошибкой или с
  /// отказом сервера забирает фокус себе, поле теряет его — и шлёт то же самое
  /// повторно, уже вторым запросом.
  bool _sending = false;

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(InlineField old) {
    super.didUpdateWidget(old);

    // Значение пришло с сервера — подхватываем. Но не пока в поле печатают:
    // иначе ответ на прошлую правку затёр бы недописанную новую.
    if (widget.value != old.value && !_focus.hasFocus) {
      _controller.text = widget.value;
    }
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) {
      _submit();
    }
  }

  Future<void> _submit() async {
    final next = _controller.text.trim();

    if (_sending || next == widget.value) {
      return;
    }

    _sending = true;

    try {
      await widget.onChanged(next);
    } finally {
      _sending = false;
    }

    // Вернулись — показываем то, что на сервере: если правка не прижилась, в
    // поле не должно остаться значение, которого в базе нет.
    if (mounted && _controller.text.trim() != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      // «Готово» даже у растущего поля: несколько строк тут нужны, чтобы
      // длинное название было видно целиком, а не чтобы вписывать переносы —
      // ни в названии товара, ни в имени поставщика их не бывает.
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        hintText: widget.hint,
        hintStyle: const TextStyle(color: Color(0xFFA3A3A3)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: _border,
        enabledBorder: _border,
        focusedBorder: _border,
        disabledBorder: _border,
      ),
    );
  }

  /// Рамки нет, но скругление есть: без него серый прямоугольник смотрится
  /// заплаткой на белом.
  OutlineInputBorder get _border => OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide.none,
  );
}
