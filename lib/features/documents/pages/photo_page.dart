import 'package:flutter/material.dart';

import '../../../shared/widgets/back_label.dart';

/// Листы накладной во весь экран.
///
/// Единственное, ради чего их открывают, — прочитать бумагу: сверить цифру,
/// разобрать номер. Поэтому здесь масштабирование двумя пальцами и чёрный фон,
/// а не аккуратная картинка в рамке.
///
/// Листов бывает несколько — тогда их листают вбок, и в шапке видно, какой
/// сейчас открыт.
class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key, required this.urls, required this.title});

  final List<String> urls;
  final String title;

  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> {
  late final PageController _pages = PageController();
  int _current = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.urls.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        // Белая, как везде: чёрная шапка над чёрным полем сливалась с ним, и
        // её приходилось искать по белой черте снизу.
        titleSpacing: 4,
        automaticallyImplyLeading: false,
        title: const BackLabel('Накладная'),
        // Черту из общей темы убираем: под шапкой чёрное поле, оно отделено
        // и так. Пустая рамка, а не `null`: `null` берёт черту из темы.
        shape: const Border(),
        actions: [
          if (many)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_current + 1} из ${widget.urls.length}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF737373),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.urls.length,
        onPageChanged: (page) => setState(() => _current = page),
        // Листаем только когда лист не увеличен: иначе перетаскивание
        // увеличенного снимка перескакивало бы на соседний.
        physics: const _PageOrZoom(),
        itemBuilder: (context, index) => _Sheet(url: widget.urls[index]),
      ),
    );
  }
}

/// Пролистывание страниц с прилипанием — обычное для `PageView`.
class _PageOrZoom extends PageScrollPhysics {
  const _PageOrZoom();

  @override
  _PageOrZoom applyTo(ScrollPhysics? ancestor) => const _PageOrZoom();
}

/// Один лист с масштабированием.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      // Мелкий шрифт накладной без хорошего увеличения не прочитать.
      maxScale: 6,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
          errorBuilder: (context, error, stack) => const Center(
            child: Text(
              'Снимок не открывается',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
