import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:image/image.dart' as img;

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../../shared/widgets/message.dart';
import '../models/shot.dart';
import '../services/documents_store.dart';

/// Съёмка накладной.
///
/// Своя камера, а не системная: только так поверх кадра рисуется рамка. Она
/// нужна не для красоты — по разбору видно, что модель ошибается, когда лист
/// снят издалека или наполовину. Рамка подсказывает поднести документ ближе.
class CapturePage extends StatefulWidget {
  const CapturePage({super.key, required this.store});

  final DocumentsStore store;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> with WidgetsBindingObserver {
  CameraController? _camera;
  bool _sending = false;
  String? _failure;

  /// Снятые листы. Накладная на две страницы — обычное дело: позиции не
  /// поместились, и продолжение напечатано на втором листе. Снимают их подряд,
  /// поэтому копим кадры здесь и отправляем разом — иначе из одного документа
  /// вышло бы два, и у второго не было бы ни поставщика, ни номера.
  final List<Shot> _pages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ушли из приложения — камеру нужно отпустить, иначе система отберёт её
    // сама и вернёмся мы к мёртвому предпросмотру.
    if (state == AppLifecycleState.inactive) {
      _camera?.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _start();
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() => _failure = 'Камера не найдена');
        return;
      }

      // `cameras.first` не гарантированно задняя камера — на части устройств
      // список начинается с фронтальной, и тогда в кадре оказывается лицо, а
      // не накладная.
      final back = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );

      final camera = CameraController(
        back.isNotEmpty ? back.first : cameras.first,
        // Накладная — это мелкий текст: на среднем разрешении строки
        // рассыпаются, и модель начинает путать цифры. `high` — это 720p,
        // на нём и рассыпались; берём столько, сколько даёт камера, а лишнее
        // срежем сами перед отправкой.
        ResolutionPreset.max,
        enableAudio: false,
      );

      await camera.initialize();

      if (!mounted) {
        await camera.dispose();
        return;
      }

      setState(() => _camera = camera);
    } on CameraException catch (error) {
      setState(
        () => _failure = error.code == 'CameraAccessDenied'
            ? 'Разрешите доступ к камере в настройках телефона'
            : 'Не удалось включить камеру',
      );
    }
  }

  /// Снимает лист и оставляет камеру открытой: следующий кадр может быть
  /// продолжением той же накладной.
  Future<void> _shoot() async {
    final camera = _camera;

    if (camera == null || _sending) {
      return;
    }

    setState(() => _sending = true);

    // Соотношение той области, в которой человек видит кадр: по ней и режем.
    final screen = MediaQuery.sizeOf(context);
    final ratio = screen.width / screen.height;

    try {
      final shot = await camera.takePicture();
      final bytes = await _fit(await shot.readAsBytes(), ratio);

      if (mounted) {
        setState(() {
          _pages.add(
            Shot(
              bytes: bytes,
              filename: 'list-${_pages.length + 1}.jpg',
              // камера отдаёт JPEG на обеих платформах
              contentType: 'image/jpeg',
            ),
          );
        });
      }
    } on CameraException {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Не удалось снять',
          message: 'Попробуйте ещё раз',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  /// Приводит снимок к тому, что человек видел в кадре.
  ///
  /// Предпросмотр показывает кадр обрезанным по краям (`BoxFit.cover`), а
  /// камера отдаёт его целиком — и на фотографии документ оказывается дальше и
  /// мельче, чем был на экране. Режем по центру под то же соотношение, а заодно
  /// ужимаем: снимать с полным разрешением нужно ради мелкого текста, а везти
  /// двенадцать мегапикселей по мобильной сети — нет.
  Future<Uint8List> _fit(Uint8List bytes, double ratio) async {
    try {
      return await compute(_fitFrame, (bytes: bytes, ratio: ratio));
    } catch (error) {
      // Не срослось — отправляем как снято: целый кадр лучше, чем никакого.
      debugPrint('Кадр не обрезался: $error');
      return bytes;
    }
  }

  /// Отправляет снятое одной накладной.
  Future<void> _send() async {
    if (_pages.isEmpty || _sending) {
      return;
    }

    setState(() => _sending = true);

    try {
      await widget.store.upload(List.of(_pages));

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Не удалось отправить',
          message: error.message,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _dropLast() {
    if (_pages.isNotEmpty) {
      setState(() => _pages.removeLast());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        // Белая, как везде в приложении: прозрачная поверх кадра выглядела
        // экраном из чужой программы, а её белая черта — единственным, что
        // отделяет шапку от чёрного.
        title: const Text('Снимок накладной'),
        // Под шапкой тёмный кадр — он отделён и без черты из общей темы.
        // Пустая рамка, а не `null`: `null` означает «взять из темы».
        shape: const Border(),
      ),
      extendBodyBehindAppBar: true,
      body: _body(),
    );
  }

  Widget _body() {
    if (_failure != null) {
      return Message(
        icon: LucideIcons.camera_off,
        title: _failure!,
        note: 'Без камеры накладную не сфотографировать',
        onRetry: () {
          setState(() => _failure = null);
          _start();
        },
      );
    }

    final camera = _camera;

    if (camera == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Предпросмотр растягиваем на весь экран с обрезкой: иначе кадр
        // соотношением 4:3 оставил бы чёрные поля, и рамка «поплыла» бы
        // относительно того, что видит камера.
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: camera.value.previewSize?.height ?? 1,
            height: camera.value.previewSize?.width ?? 1,
            child: CameraPreview(camera),
          ),
        ),
        const DocumentFrame(),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: CaptureControls(
            busy: _sending,
            pages: _pages.length,
            onPressed: _shoot,
            onSend: _send,
            onUndo: _dropLast,
          ),
        ),
      ],
    );
  }
}

/// Насколько большим отправляем снимок. Сервер всё равно ужимает до 2200, но
/// запас на его собственную обрезку полей не помешает.
const _maxSide = 2400;

/// Обрезка и сжатие в отдельном потоке: двенадцать мегапикселей в главном
/// подвешивают экран на секунду с лишним.
Uint8List _fitFrame(({Uint8List bytes, double ratio}) frame) {
  final decoded = img.decodeImage(frame.bytes);

  if (decoded == null) {
    return frame.bytes;
  }

  // Телефон пишет ориентацию в EXIF, а не поворачивает пиксели: без этого
  // портретный снимок пришёл бы лежащим на боку, и резали бы мы не то.
  final upright = img.bakeOrientation(decoded);
  final cropped = cropToRatio(upright, frame.ratio);
  final longest = cropped.width > cropped.height
      ? cropped.width
      : cropped.height;

  final sized = longest > _maxSide
      ? img.copyResize(
          cropped,
          width: cropped.width >= cropped.height ? _maxSide : null,
          height: cropped.height > cropped.width ? _maxSide : null,
          interpolation: img.Interpolation.average,
        )
      : cropped;

  return img.encodeJpg(sized, quality: 90);
}

/// Центральная часть кадра с нужным соотношением сторон.
@visibleForTesting
img.Image cropToRatio(img.Image image, double ratio) {
  final current = image.width / image.height;

  if ((current - ratio).abs() < 0.01) {
    return image;
  }

  // Кадр шире нужного — режем по бокам, уже — сверху и снизу. Ровно это и
  // делает предпросмотр, растянутый с обрезкой.
  final width = current > ratio ? (image.height * ratio).round() : image.width;
  final height = current > ratio ? image.height : (image.width / ratio).round();

  return img.copyCrop(
    image,
    x: ((image.width - width) / 2).round(),
    y: ((image.height - height) / 2).round(),
    width: width,
    height: height,
  );
}

/// Нижний ряд экрана съёмки: спуск, а рядом — что делать со снятым.
///
/// Раньше здесь была одна кнопка: снял — отправилось. Накладная на двух листах
/// так превращалась в два документа, у второго из которых нет ни поставщика,
/// ни номера, — поэтому снятое копится, и отправку человек подтверждает сам.
@visibleForTesting
class CaptureControls extends StatelessWidget {
  const CaptureControls({
    super.key,
    required this.busy,
    required this.pages,
    required this.onPressed,
    required this.onSend,
    required this.onUndo,
  });

  final bool busy;

  /// Сколько листов уже снято.
  final int pages;

  final VoidCallback onPressed;
  final VoidCallback onSend;
  final VoidCallback onUndo;

  /// Высота этого блока. `DocumentFrame` вычитает её из доступного места,
  /// чтобы своё окно сюда не запускало.
  static const double height = _ShutterButton.size + 34;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 26,
            child: pages == 0
                ? null
                : Text(
                    pages == 1 ? 'Снят 1 лист' : 'Снято листов: $pages',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
          ),
          Row(
            children: [
              // Слева — отменить последний кадр, справа — отправить. Обе кнопки
              // держат своё место всегда, иначе спуск съезжал бы вбок после
              // первого же снимка.
              Expanded(
                child: pages == 0
                    ? const SizedBox.shrink()
                    : _SideButton(
                        icon: LucideIcons.undo_2,
                        label: 'Убрать',
                        onPressed: busy ? null : onUndo,
                      ),
              ),
              _ShutterButton(busy: busy, onPressed: onPressed),
              Expanded(
                child: pages == 0
                    ? const SizedBox.shrink()
                    : _SideButton(
                        icon: LucideIcons.circle_check_big,
                        label: 'Готово',
                        highlighted: true,
                        onPressed: busy ? null : onSend,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Кнопка сбоку от спуска: иконка с подписью на тёмном кадре.
class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null
        ? Colors.white38
        : highlighted
        ? const Color(0xFF7DD3FC)
        : Colors.white;

    return TextButton(
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

/// Затемнение с прозрачным окном под лист.
///
/// Окно ищет место в полосе между шапкой и `CaptureControls` снизу — не на
/// всём экране, иначе на невысоких телефонах ему не хватает соседей, и оно
/// заезжает в то место, где стоят подсказка и кнопка.
@visibleForTesting
class DocumentFrame extends StatelessWidget {
  const DocumentFrame({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    // Сверху — шапка со статус-баром и небольшой отступ, снизу — весь блок
    // CaptureControls плюс то, что откусывает безопасная зона телефона.
    final topInset = kToolbarHeight + padding.top + 16;
    final bottomInset =
        CaptureControls.height + (padding.bottom < 16 ? 16 : padding.bottom);

    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleHeight = (constraints.maxHeight - topInset - bottomInset)
            .clamp(0.0, constraints.maxHeight);

        // Пропорции листа A4, в которые и печатают накладные.
        final width = constraints.maxWidth * 0.86;
        final height = (width * 1.414).clamp(0.0, visibleHeight);
        final window = Rect.fromCenter(
          center: Offset(
            constraints.maxWidth / 2,
            topInset + visibleHeight / 2,
          ),
          width: width,
          height: height,
        );

        return IgnorePointer(
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _FramePainter(window),
          ),
        );
      },
    );
  }
}

/// Рисует затемнение с окном и уголки по его краям.
class _FramePainter extends CustomPainter {
  const _FramePainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(window, const Radius.circular(12));

    // Затемняем всё, кроме окна: разница чётко показывает, куда целиться.
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

    // Уголки вместо сплошной рамки: они обозначают границы, но не спорят с
    // самим документом, который человек в них разглядывает.
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
  bool shouldRepaint(_FramePainter old) => old.window != window;
}

/// Круглая кнопка спуска.
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onPressed});

  static const double size = 72;

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: busy ? 0.4 : 1),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.6),
            width: 4,
          ),
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(22),
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : null,
      ),
    );
  }
}
