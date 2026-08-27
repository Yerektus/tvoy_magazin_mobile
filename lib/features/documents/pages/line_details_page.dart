import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../../shared/widgets/inline_field.dart';
import '../../umag/models/umag_account.dart';
import '../../umag/services/umag_store.dart';
import '../models/document.dart';
import '../services/documents_store.dart';
import 'barcode_scan_page.dart';

/// Позиция накладной: что прочитала модель и как это поправить.
///
/// Поля правятся прямо на странице — окно на каждое значение заставляло бы
/// открывать и закрывать его шесть раз подряд, а строку обычно правят целиком.
/// Уходит правка по одной, как только поле теряет фокус: копить их и слать
/// пачкой по кнопке было бы привычнее, но тогда закрытая по ошибке страница
/// молча теряет работу.
class LineDetailsPage extends StatefulWidget {
  const LineDetailsPage({
    super.key,
    required this.store,
    required this.umag,
    required this.invoiceId,
    required this.line,
  });

  final DocumentsStore store;

  /// Кабинет нужен ради полок: у товара, которого там ещё нет, человек
  /// выбирает категорию.
  final UmagAccountStore umag;

  final int invoiceId;
  final DocumentLine line;

  @override
  State<LineDetailsPage> createState() => _LineDetailsPageState();
}

class _LineDetailsPageState extends State<LineDetailsPage> {
  late DocumentLine _line = widget.line;
  bool _saving = false;

  /// Полки кабинета. Пусто, пока не приехали или пока кабинет не подключён —
  /// тогда категорию не спрашиваем, товар уедет в «Незаданные».
  List<UmagCategory> _categories = const [];

  /// Правил ли человек хоть что-то: по этому список на прошлой странице решает,
  /// перечитывать ли себя.
  bool _changed = false;

  @override
  void initState() {
    super.initState();

    // Полки нужны только тому товару, которого в кабинете ещё нет: остальным
    // спрашивать их незачем, а список длинный.
    if (widget.line.umagMissing) {
      _loadCategories();
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await widget.umag.categories();

      if (mounted) {
        setState(() => _categories = categories);
      }
    } on ApiException {
      // Молча: без списка полка просто не выбирается, а карточка позиции
      // остаётся рабочей.
    }
  }

  Future<void> _edit(String field, String next, {bool numeric = false}) async {
    // Запятую с телефонной клавиатуры сервер не поймёт — она там вместо точки.
    final prepared = numeric ? next.replaceAll(',', '.') : next;

    if (numeric && prepared.isNotEmpty && double.tryParse(prepared) == null) {
      await showErrorDialog(
        context,
        title: 'Тут нужно число',
        message: 'Например: 12 или 8.29',
      );
      return;
    }

    await _save({field: prepared.isEmpty ? null : prepared});
  }

  /// Считывает штрихкод камерой и кладёт его в поле.
  ///
  /// Набирать тринадцать цифр с этикетки руками — самое долгое и самое
  /// ошибочное место в правке позиции: одна цифра мимо, и кабинет не найдёт
  /// товар, а понять, где именно опечатка, по такому числу невозможно.
  Future<void> _scanBarcode() async {
    // Клавиатуру убираем заранее: иначе поле теряет фокус уже после того, как
    // сканер вернул код, и следом отправляет старое значение поверх нового.
    FocusManager.instance.primaryFocus?.unfocus();

    final code = await BarcodeScanPage.open(context);

    if (code == null || !mounted || code == _line.barcode) {
      return;
    }

    await _edit('barcode', code, numeric: true);
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    setState(() => _saving = true);

    try {
      final detail = await widget.store.updateLine(
        widget.invoiceId,
        _line.id,
        patch,
      );
      final fresh = detail.lines.where((line) => line.id == _line.id);

      if (mounted) {
        setState(() {
          _changed = true;
          if (fresh.isNotEmpty) {
            _line = fresh.first;
          }
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Не удалось сохранить',
          message: error.message,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop(_changed);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Позиция ${_line.position}',
            style: const TextStyle(fontSize: 16),
          ),
          bottom: _saving
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _Field(
              label: 'Название',
              value: _line.name,
              maxLines: null,
              onChanged: (next) => _edit('name', next),
            ),
            _Field(
              label: 'Штрихкод',
              value: _line.barcode,
              hint: '8–14 цифр',
              note: _line.barcodeAuto ? 'из прошлых накладных' : null,
              keyboardType: TextInputType.number,
              onChanged: (next) => _edit('barcode', next, numeric: true),
              // Кнопка внутри поля, а не рядом: она про это самое значение, и
              // отдельной кнопкой её пришлось бы ещё связать глазами с нужной
              // строкой из шести.
              suffix: IconButton(
                onPressed: _saving ? null : _scanBarcode,
                icon: const Icon(LucideIcons.scan_barcode, size: 20),
                color: const Color(0xFF0284C7),
                tooltip: 'Сканировать штрихкод',
              ),
            ),
            _Field(
              label: 'Количество',
              value: numberForInput(_line.quantity),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (next) => _edit('quantity', next, numeric: true),
            ),
            _Field(
              label: 'Единица',
              value: _line.unit,
              hint: 'шт, бут., кор.',
              onChanged: (next) => _edit('unit', next),
            ),
            _Field(
              label: 'Цена',
              value: numberForInput(_line.price),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (next) => _edit('price', next, numeric: true),
            ),
            _Field(
              label: 'Сумма',
              value: numberForInput(_line.total),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (next) => _edit('total', next, numeric: true),
            ),
            if (_line.umagProductName.isNotEmpty)
              // Сопоставление ведёт сам кабинет: у нас правят штрихкод, а товар
              // подбирается по нему заново.
              _ReadOnly(label: 'Товар в UMAG', value: _line.umagProductName),

            // Товара с таким штрихкодом в кабинете нет — заведём его при
            // отправке. Поля те же, что в форме кабинета: под каким названием
            // положить, на какую полку, чем меряют и почём продавать.
            if (_line.umagMissing) ..._newProduct(),
          ],
        ),
      ),
    );
  }

  /// Поля новой карточки товара.
  List<Widget> _newProduct() {
    return [
      const _Caption('Новый товар в UMAG'),
      _Field(
        label: 'Название',
        value: _line.umagNewName,
        hint: _line.name,
        maxLines: null,
        note: 'как товар будет называться в кабинете',
        onChanged: (next) => _edit('umag_new_name', next),
      ),
      _Choice(
        // Не «единица»: она уже есть выше, в самой строке накладной. Здесь то,
        // чем кабинет отличает штучную карточку от весовой.
        label: 'Тип товара',
        value: _line.umagNewMeasure ?? 0,
        options: const {0: 'Штучный', 1: 'Весовой', 2: 'Разливной'},
        enabled: !_saving,
        onChanged: (next) => _edit('umag_new_measure', '$next'),
      ),
      if (_categories.isNotEmpty)
        _Choice(
          label: 'Категория',
          value: _line.umagNewCategoryId ?? _categories.first.id,
          options: {
            for (final category in _categories) category.id: category.name,
          },
          enabled: !_saving,
          onChanged: (next) => _edit('umag_new_category_id', '$next'),
        ),
      _Field(
        label: 'Цена продажи',
        value: numberForInput(_line.umagNewSellingPrice),
        hint: numberForInput(_line.price),
        note: 'пусто — продаём по цене прихода',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (next) =>
            _edit('umag_new_selling_price', next, numeric: true),
      ),
    ];
  }
}

/// Подпись над группой полей.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: Color(0xFFA3A3A3)),
      ),
    );
  }
}

/// Выбор одного значения из списка — тем же рядом, что и поля.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Map<int, String> options;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF737373)),
            ),
          ),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: options.containsKey(value) ? value : null,
              isExpanded: true,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                border: _border,
                enabledBorder: _border,
                focusedBorder: _border,
                disabledBorder: _border,
              ),
              items: [
                for (final option in options.entries)
                  DropdownMenuItem<int>(
                    value: option.key,
                    child: Text(option.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: enabled
                  ? (next) => next == null ? null : onChanged(next)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Такая же серая заливка без рамки, как у правимых полей рядом.
  OutlineInputBorder get _border => OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide.none,
  );
}

/// Строка «подпись — поле».
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.note,
    this.keyboardType,
    this.maxLines = 1,
    this.suffix,
  });

  final String label;
  final String value;
  final Future<void> Function(String) onChanged;
  final String? hint;
  final String? note;
  final TextInputType? keyboardType;
  final int? maxLines;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 11),
            child: SizedBox(
              width: 110,
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF737373)),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InlineField(
                  value: value,
                  hint: hint,
                  keyboardType: keyboardType,
                  maxLines: maxLines,
                  onChanged: onChanged,
                  suffix: suffix,
                ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Text(
                      note!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// То, что показываем, но не даём править.
class _ReadOnly extends StatelessWidget {
  const _ReadOnly({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF737373)),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
