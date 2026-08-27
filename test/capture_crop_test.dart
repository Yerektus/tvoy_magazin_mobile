import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tvoy_magazin_mobile/features/documents/pages/capture_page.dart';

/// Снимок должен совпадать с тем, что человек видел в кадре: предпросмотр
/// показывает его обрезанным по краям, а камера отдаёт целиком — и на
/// фотографии документ оказывался дальше и мельче, чем был на экране.
void main() {
  /// Экран телефона: узкий и длинный.
  const phone = 1080 / 2340;

  test('широкий кадр камеры режется по бокам', () {
    final frame = img.Image(width: 3000, height: 4000);

    final cropped = cropToRatio(frame, phone);

    expect(cropped.width / cropped.height, closeTo(phone, 0.01));
    // По высоте кадр не трогаем: узкий экран отрезает именно бока.
    expect(cropped.height, 4000);
    expect(cropped.width, lessThan(3000));
  });

  test('обрезанное берётся из середины кадра', () {
    final frame = img.Image(width: 3000, height: 4000);

    // Красим полосу ровно по центру — она обязана остаться.
    for (var y = 0; y < frame.height; y++) {
      frame.setPixelRgb(frame.width ~/ 2, y, 255, 0, 0);
    }

    final cropped = cropToRatio(frame, phone);
    final middle = cropped.getPixel(cropped.width ~/ 2, 10);

    expect(middle.r, 255);
    expect(middle.g, 0);
  });

  test('кадр нужного соотношения остаётся как есть', () {
    final frame = img.Image(width: 1080, height: 2340);

    final cropped = cropToRatio(frame, phone);

    expect(cropped.width, 1080);
    expect(cropped.height, 2340);
  });
}
