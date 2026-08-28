import '../models/shot.dart';
import 'document_scanner.dart';

/// В браузере системного сканера документов нет.
///
/// Приложение там открывают для отладки, и снимать накладную камерой ноутбука
/// всё равно некому: страница честно говорит, что сканера нет, а вызывающий
/// откатывается на свою камеру.
class PlatformScanner implements DocumentScanner {
  const PlatformScanner();

  @override
  Future<List<Shot>> scan() async {
    throw const ScannerUnavailable('В браузере сканера документов нет');
  }
}
