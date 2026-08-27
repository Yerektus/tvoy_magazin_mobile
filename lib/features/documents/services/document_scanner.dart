import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:content_resolver/content_resolver.dart';

import '../models/shot.dart';

/// Съёмка накладной системным сканером документов.
///
/// На андроиде это ML Kit Document Scanner, на айфоне — VisionKit. Оба сами
/// находят края листа, выпрямляют перспективу и поднимают контраст: модель
/// читает такой снимок заметно лучше, чем кадр «как получилось». Своей камерой
/// мы этого не умеем — там человек целится в рамку и снимает лист под углом.
///
/// Сканер может быть недоступен: на андроиде он живёт в сервисах Google, и на
/// телефоне без них не откроется. Тогда бросаем [ScannerUnavailable], а
/// вызывающий откатывается на свою камеру.
class DocumentScanner {
  const DocumentScanner();

  /// Сколько листов даём снять за раз. Накладная на четыре страницы — уже
  /// редкость, но бывает.
  static const pages = 8;

  /// Открывает сканер и отдаёт снятые листы. Пусто — сканер закрыли, ничего
  /// не сняв.
  Future<List<Shot>> scan() async {
    try {
      final result = await FlutterDocScanner().getScannedDocumentAsImages(
        page: pages,
      );

      if (result == null) {
        return const [];
      }

      final shots = <Shot>[];

      for (final (index, uri) in result.images.indexed) {
        shots.add(await _read(uri, index + 1));
      }

      return shots;
    } on DocScanException catch (error) {
      // Закрыли сканер — это не поломка, а отказ: возвращаем пусто.
      if (error.code == DocScanException.codeCancelled) {
        return const [];
      }

      throw ScannerUnavailable(error.message);
    } on MissingPluginException catch (error) {
      throw ScannerUnavailable(error.message ?? 'Сканер недоступен');
    }
  }

  /// Читает снятый лист.
  ///
  /// Айфон отдаёт путь к файлу, андроид — `content://`-ссылку своего
  /// хранилища: её нельзя открыть как файл, за содержимым нужно идти к системе.
  Future<Shot> _read(String uri, int number) async {
    final bytes = uri.startsWith('content://')
        ? (await ContentResolver.resolveContent(uri)).data
        : await File(uri.replaceFirst('file://', '')).readAsBytes();

    return Shot(
      bytes: bytes,
      filename: 'list-$number.jpg',
      // Оба сканера отдают JPEG; на айфоне мы просим его явно.
      contentType: 'image/jpeg',
    );
  }
}

/// Сканера на этом телефоне нет — снимать придётся своей камерой.
class ScannerUnavailable implements Exception {
  const ScannerUnavailable(this.message);

  final String message;

  @override
  String toString() => 'ScannerUnavailable: $message';
}
