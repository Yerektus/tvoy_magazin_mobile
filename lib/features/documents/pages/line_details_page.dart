import 'package:flutter/material.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../../shared/widgets/inline_field.dart';
import '../models/document.dart';
import '../services/documents_store.dart';

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
    required this.invoiceId,
    required this.line,
  });

  final DocumentsStore store;
  final int invoiceId;
  final DocumentLine line;

  @override
  State<LineDetailsPage> createState() => _LineDetailsPageState();
}

class _LineDetailsPageState extends State<LineDetailsPage> {
  late DocumentLine _line = widget.line;
  bool _saving = false;

  /// Правил ли человек хоть что-то: по этому список на прошлой странице решает,
  /// перечитывать ли себя.
  bool _changed = false;

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

  Future<void> _save(Map<String, dynamic> patch) async {
    setState(() => _saving = true);

    try {
      final detail =
          await widget.store.updateLine(widget.invoiceId, _line.id, patch);
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
              note: _line.barcodeGuessed ? 'подставил ИИ' : null,
              keyboardType: TextInputType.number,
              onChanged: (next) => _edit('barcode', next, numeric: true),
            ),
            _Field(
              label: 'Количество',
              value: numberForInput(_line.quantity),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (next) => _edit('price', next, numeric: true),
            ),
            _Field(
              label: 'Сумма',
              value: numberForInput(_line.total),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (next) => _edit('total', next, numeric: true),
            ),
            if (_line.umagProductName.isNotEmpty)
              // Сопоставление ведёт сам кабинет: у нас правят штрихкод, а товар
              // подбирается по нему заново.
              _ReadOnly(label: 'Товар в UMAG', value: _line.umagProductName),
          ],
        ),
      ),
    );
  }
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
  });

  final String label;
  final String value;
  final Future<void> Function(String) onChanged;
  final String? hint;
  final String? note;
  final TextInputType? keyboardType;
  final int? maxLines;

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
