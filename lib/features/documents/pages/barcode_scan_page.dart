import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../shared/widgets/app_theme.dart';
import '../../../shared/widgets/message.dart';

/// Сканирование штрихкода товара.
///
/// Возвращает прочитанный код через `Navigator.pop`, либо `null`, если человек
/// передумал. Ничего не сохраняет сама: где этот код пригодится, знает та
/// страница, которая её открыла.
class BarcodeScanPage extends StatefulWidget {
  const BarcodeScanPage({super.key});

  /// Открывает сканер и отдаёт прочитанный код.
  static Future<String?> open(BuildContext context) => Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const BarcodeScanPage()));

  @override
  State<BarcodeScanPage> createState() => _BarcodeScanPageState();
}

class _BarcodeScanPageState extends State<BarcodeScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    // Только товарные форматы. QR и прочее камера читает не хуже, но в поле
    // штрихкода им делать нечего, а лишний формат — лишний шанс прочитать не
    // ту наклейку на коробке.
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf14,
      BarcodeFormat.code128,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
    // Штрихкод на пакете сока — это полоски шириной в треть миллиметра, и на
    // низком разрешении они сливаются. Просим полное HD, но только на айфоне:
    // на андроиде CameraX подбирает размер сам под возможности камеры, а
    // навязанный размер он молча заменяет ближайшим — и кадр анализа перестаёт
    // совпадать с тем, что видно на экране.
    cameraResolution: Platform.isIOS ? const Size(1920, 1080) : null,
    // Код мелкий и телефон держат в полуметре — камера подтягивает его сама.
    // Работает только на андроиде; на айфоне ту же задачу решает объектив
    // ближней съёмки, см. `_useCloseRangeLens`.
    autoZoom: true,
  );

  /// Код уже прочитан и страница закрывается. Без этого камера успевает
  /// прислать второй кадр с тем же кодом, и `pop` уходит дважды — вместе с
  /// экраном закрывается и карточка позиции под ним.
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _useCloseRangeLens();
  }

  /// Переключается на объектив, которым лучше видно вблизи.
  ///
  /// У новых айфонов таких несколько, и обычный на расстоянии ладони не
  /// наводится: кадр плывёт, а полоски штрихкода не разделяются. Ультраширокий
  /// с макро на этой дистанции читает сразу. Не вышло — остаёмся на обычном:
  /// сканер и с ним работает, просто хуже.
  Future<void> _useCloseRangeLens() async {
    try {
      final best = await _controller.getBestCloseRangeScanningLens();
      final supported = await _controller.getSupportedLenses(
        facing: CameraFacing.back,
      );

      if (best == null || !supported.contains(best) || !mounted) {
        return;
      }

      await _controller.switchCamera(
        SelectCamera(facingDirection: CameraFacing.back, lensType: best),
      );
    } on MobileScannerException catch (error) {
      debugPrint('Ближний объектив недоступен: ${error.errorCode}');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) {
      return;
    }

    final codes = capture.barcodes
        .map((barcode) => barcode.rawValue ?? '')
        .where((code) => code.isNotEmpty);

    if (codes.isEmpty) {
      return;
    }

    _done = true;

    // Короткий отклик: экран закрывается сам, и без него непонятно, прочитался
    // код или сканер просто закрыли рукой.
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(codes.first);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        // Белая, как везде в приложении. Прозрачная поверх кадра выглядела
        // отдельным экраном из чужой программы, а чёрное на чёрном ещё и
        // сливалось: было не понять, где кончается шапка и начинается камера.
        title: const Text('Штрихкод'),
        // Пустая рамка, а не `null`: `null` означает «взять из темы», а в теме
        // черта под шапкой есть. Здесь она лишняя — под шапкой тёмный кадр, он
        // отделён и так.
        shape: const Border(),
        actions: [
          _TorchButton(controller: _controller),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final window = _window(context, constraints);

          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                // Тап наводит фокус: на андроиде камера с автофокусом норовит
                // поймать полку за спиной, а не этикетку в руке.
                tapToFocus: true,
                // Читаем только то, что попало в окно: на полке рядом стоят
                // соседние коробки, и без окна сканер хватает их штрихкоды.
                scanWindow: window,
                onDetect: _onDetect,
                // Ошибку кладём на белое: кадра нет, а тёмными буквами по
                // чёрному фону не прочитать, почему камера не включилась.
                errorBuilder: (context, error) => ColoredBox(
                  color: Colors.white,
                  child: Message(
                    icon: LucideIcons.camera_off,
                    title:
                        error.errorCode ==
                            MobileScannerErrorCode.permissionDenied
                        ? 'Разрешите доступ к камере в настройках телефона'
                        : 'Не удалось включить камеру',
                    note: 'Штрихкод можно набрать и руками',
                  ),
                ),
              ),
              IgnorePointer(
                child: CustomPaint(painter: _WindowPainter(window)),
              ),
              Positioned(
                left: 24,
                right: 24,
                top: window.bottom + 20,
                child: const Text(
                  'Наведите окно на штрихкод',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Окно сканирования: широкое и низкое — такой и есть полоска штрихкода.
  /// Стоит выше середины, чтобы читаемое не закрывала рука с телефоном.
  Rect _window(BuildContext context, BoxConstraints constraints) {
    final width = constraints.maxWidth * 0.92;

    return Rect.fromCenter(
      center: Offset(constraints.maxWidth / 2, constraints.maxHeight * 0.42),
      width: width,
      // Окно широкое и высокое: узкое требовало прицеливаться, а штрихкод на
      // коробке лежит то вдоль, то поперёк, и промах по окну человек читает
      // как «сканер не работает».
      height: (width * 0.75).clamp(160.0, 320.0),
    );
  }
}

/// Фонарик. Штрихкоды читают в подсобке и в холодильнике, где темно.
class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (context, state, _) {
        // Фонарика может не быть вовсе — на таком телефоне кнопке нечего
        // включать, и показывать её незачем.
        if (state.torchState == TorchState.unavailable) {
          return const SizedBox.shrink();
        }

        final on = state.torchState == TorchState.on;

        return IconButton(
          onPressed: controller.toggleTorch,
          tooltip: on ? 'Выключить фонарик' : 'Включить фонарик',
          icon: Icon(
            on ? LucideIcons.flashlight_off : LucideIcons.flashlight,
            color: on ? accentDark : const Color(0xFF404040),
          ),
        );
      },
    );
  }
}

/// Затемнение с прозрачным окном и уголками по краям — как на съёмке
/// накладной, чтобы два экрана камеры не выглядели из разных приложений.
class _WindowPainter extends CustomPainter {
  const _WindowPainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(window, const Radius.circular(12));

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(rounded),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const arm = 26.0;
    for (final (corner, dx, dy) in [
      (window.topLeft, 1.0, 1.0),
      (window.topRight, -1.0, 1.0),
      (window.bottomLeft, 1.0, -1.0),
      (window.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner, corner.translate(arm * dx, 0), line);
      canvas.drawLine(corner, corner.translate(0, arm * dy), line);
    }
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}
