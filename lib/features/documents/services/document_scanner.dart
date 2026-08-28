import '../models/shot.dart';
import 'document_scanner_web.dart'
    if (dart.library.io) 'document_scanner_phone.dart';

/// Съёмка накладной системным сканером документов.
///
/// На андроиде это ML Kit Document Scanner, на айфоне — VisionKit. Оба сами
/// находят края листа, выпрямляют перспективу и поднимают контраст: модель
/// читает такой снимок заметно лучше, чем кадр «как получилось». Своей камерой
/// мы этого не умеем — там человек целится в рамку и снимает лист под углом.
///
/// Реализацию выбирает платформа: телефонная тянет за собой `dart:io` и чтение
/// `content://`-ссылок через `dart:ffi`, а в браузере ни того, ни другого нет —
/// туда идёт заглушка, иначе не собирается всё приложение.
abstract interface class DocumentScanner {
  /// Сканер этой платформы.
  factory DocumentScanner() = PlatformScanner;

  /// Открывает сканер и отдаёт снятые листы. Пусто — сканер закрыли, ничего
  /// не сняв. Бросает [ScannerUnavailable], если сканера на устройстве нет.
  Future<List<Shot>> scan();
}

/// Сканера на этом устройстве нет — снимать придётся своей камерой.
class ScannerUnavailable implements Exception {
  const ScannerUnavailable(this.message);

  final String message;

  @override
  String toString() => 'ScannerUnavailable: $message';
}
