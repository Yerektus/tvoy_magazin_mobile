// Готовит картинки для иконок приложения из логотипа.
//
// `storefront.png` — сам логотип во весь квадрат: он идёт в иконку айфона, где
// прозрачности быть не должно. `storefront_adaptive.png` — тот же логотип,
// уменьшенный и по центру: у андроида иконку обрезают маской (круг, капля,
// квадрат со скруглением), и без полей по краям витрине срезало бы навес.
//
// Запуск: dart run tool/make_icons.dart
import 'dart:io';

import 'package:image/image.dart' as img;

/// Какую долю квадрата занимает логотип на андроидной иконке. Внешняя четверть
/// у маски уходит под обрезку.
const scale = 0.62;

void main() {
  final source = img.decodePng(File('assets/logo/storefront.png').readAsBytesSync());

  if (source == null) {
    stderr.writeln('Не читается assets/logo/storefront.png');
    exit(1);
  }

  final side = source.width;
  final inner = (side * scale).round();
  final logo = img.copyResize(source, width: inner, height: inner);
  final canvas = img.Image(width: side, height: side, numChannels: 4);

  img.compositeImage(
    canvas,
    logo,
    dstX: ((side - inner) / 2).round(),
    dstY: ((side - inner) / 2).round(),
  );

  File('assets/logo/storefront_adaptive.png').writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Готово: $side×$side, логотип $inner×$inner');
}
