import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvoy_magazin_mobile/features/documents/models/document.dart';
import 'package:tvoy_magazin_mobile/features/documents/pages/document_details_page.dart';
import 'package:tvoy_magazin_mobile/features/documents/pages/photo_page.dart';
import 'package:tvoy_magazin_mobile/features/documents/services/documents_store.dart';
import 'package:tvoy_magazin_mobile/features/umag/models/umag_account.dart';
import 'package:tvoy_magazin_mobile/features/umag/services/umag_store.dart';
import 'package:tvoy_magazin_mobile/shared/services/api_client.dart';
import 'package:tvoy_magazin_mobile/shared/services/api_exception.dart';
import 'package:tvoy_magazin_mobile/shared/widgets/app_theme.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

/// Подменяет сеть: помнит, что и куда ушло.
class _FakeApi extends ApiClient {
  _FakeApi({
    this.status = 'checked',
    this.image = 'http://server/media/1.jpg',
    this.images,
    this.supplyId,
  });

  String status;
  final String? image;

  /// Все листы накладной. Не задан — лист один, тот что в `image`.
  final List<String>? images;

  final int? supplyId;
  final List<String> posts = [];
  final List<String> deletes = [];
  int gets = 0;

  /// Сколько раз спрашивали кабинет UMAG.
  int umagAsked = 0;

  /// Сервер отвечает отказом на удаление.
  bool refuseDelete = false;

  /// Насколько сервер задумывается перед ответом. Ноль — мгновенно, и тогда
  /// состояния «идёт работа» на экране просто не бывает: проверять в нём
  /// нечего.
  Duration delay = Duration.zero;

  /// Строки накладной. Удаление выкидывает строку и перенумеровывает
  /// оставшиеся — ровно как сервер.
  List<Map<String, dynamic>> lines = [
    {
      'id': 765,
      'position': 1,
      'name': 'Сырок Чудо',
      'quantity': '3.000',
      'unit': 'шт',
      'total': '1125.00',
    },
    {
      'id': 766,
      'position': 2,
      'name': 'Каша Агуша',
      'quantity': '2.000',
      'unit': 'шт',
      'total': '750.00',
    },
  ];

  @override
  Future<dynamic> delete(String path) async {
    deletes.add(path);
    await Future<void>.delayed(delay);

    if (refuseDelete) {
      throw ApiException('Позиция уже удалена');
    }

    final id = int.parse(path.split('/')[4]);
    lines = lines.where((line) => line['id'] != id).toList();

    for (var i = 0; i < lines.length; i++) {
      lines[i] = {...lines[i], 'position': i + 1};
    }

    return null;
  }

  @override
  Future<dynamic> post(String path, Object body) async {
    posts.add(path);

    if (path == '/invoices/87/check/') {
      status = 'checked';
      return _invoice();
    }

    if (path == '/umag/invoices/87/') {
      return <String, dynamic>{'supply_id': 123456};
    }

    return _invoice();
  }

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    if (path == '/invoices/87/') {
      gets++;
      return _invoice();
    }

    if (path == '/umag/account/') {
      umagAsked++;
      return <String, dynamic>{
        'connected': true,
        'store_id': 17797,
        'stores': [
          {'id': 17795, 'name': 'Каратал'},
          {'id': 17796, 'name': 'Еркин'},
          {'id': 17797, 'name': 'Курманова'},
        ],
      };
    }

    return <String, dynamic>{'results': <dynamic>[]};
  }

  Map<String, dynamic> _invoice() => <String, dynamic>{
    'id': 87,
    'status': status,
    'supplier': 'ТОО «КАРАВАН»',
    'supplier_bin': '220340013017',
    'number': 'KBH0425963',
    'total': '17086.00',
    'image': image,
    'images': images ?? [?image],
    'umag_supply_id': supplyId,
    'lines': lines,
  };
}

const _item = DocumentItem(
  id: 87,
  status: DocumentStatus.checked,
  supplier: 'ТОО «КАРАВАН»',
  number: 'KBH0425963',
  issuedAt: null,
  total: 17086,
  linesCount: 0,
  createdAt: null,
);

void main() {
  Future<void> pump(WidgetTester tester, _FakeApi api) async {
    // Окно по умолчанию (800×600) слишком низкое: позиции уходят под нижнюю
    // панель с итогом, и свайп по ним промахивается мимо строки.
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: DocumentDetailsPage(
          store: DocumentsStore(api: api),
          item: _item,
          umag: UmagAccountStore(api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('снимка на странице нет — только кнопка, открывающая его', (
    tester,
  ) async {
    final api = _FakeApi();
    await pump(tester, api);

    // Превью убрано: картинка на самой странице не рисуется.
    expect(find.byType(Image), findsNothing);

    await tester.tap(find.byTooltip('Открыть снимок'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoPage), findsOneWidget);
  });

  testWidgets('без снимка кнопки нет', (tester) async {
    await pump(tester, _FakeApi(image: null));

    expect(find.byTooltip('Открыть снимок'), findsNothing);
  });

  testWidgets('итог стоит внизу, а не в шапке', (tester) async {
    await pump(tester, _FakeApi());

    final total = find.text('17\u00a0086\u00a0₸');
    expect(total, findsOneWidget);

    // Ниже середины экрана — то есть в нижней панели, а не в AppBar.
    final height =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getCenter(total).dy, greaterThan(height / 2));
  });

  testWidgets('пока накладная разбирается, страница перечитывает себя', (
    tester,
  ) async {
    final api = _FakeApi(status: 'processing');

    await tester.pumpWidget(
      MaterialApp(
        home: DocumentDetailsPage(
          store: DocumentsStore(api: api),
          item: _item,
          umag: UmagAccountStore(api: api),
        ),
      ),
    );
    // `pumpAndSettle` тут не годится: у страницы намеренно висит таймер, и
    // ждать тишины пришлось бы до самого тайм-аута.
    await tester.pump();
    await tester.pump();

    expect(api.gets, 1);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(api.gets, 2, reason: 'опрос не сработал');

    // Уводим страницу с экрана — иначе висящий таймер уронит проверку в конце.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('когда разбор закончен, опрос не заводится', (tester) async {
    final api = _FakeApi();
    await pump(tester, api);

    await tester.pump(const Duration(seconds: 10));

    expect(api.gets, 1);
  });

  testWidgets('разобранную предлагают отметить проверенной', (tester) async {
    final api = _FakeApi(status: 'done');
    await pump(tester, api);

    expect(find.text('Проверено'), findsWidgets);
    // Отправлять нечего, пока никто не сверил с бумагой.
    expect(find.text('Загрузить в UMAG'), findsNothing);

    await tester.tap(find.text('Проверено').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Проверено').last);
    await tester.pumpAndSettle();

    expect(api.posts, ['/invoices/87/check/']);
  });

  testWidgets('проверенную предлагают загрузить в UMAG', (tester) async {
    final api = _FakeApi();
    await pump(tester, api);

    expect(find.text('Загрузить в UMAG'), findsOneWidget);

    await tester.tap(find.text('Загрузить в UMAG'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Загрузить'));
    await tester.pumpAndSettle();

    expect(api.posts, ['/umag/invoices/87/']);
    expect(find.textContaining('123456'), findsOneWidget);
  });

  testWidgets('уже отправленную второй раз не предлагают', (tester) async {
    await pump(tester, _FakeApi(supplyId: 999));

    expect(find.text('Загрузить в UMAG'), findsNothing);
    expect(find.text('Черновик в UMAG'), findsOneWidget);
  });

  testWidgets(
    'перераспознанная, но отправленная зовёт в кабинет, а не на проверку',
    (tester) async {
      // Разбор сбросил статус на «Готово», но черновик в UMAG уже есть: заводить
      // второй нельзя, поэтому и отмечать заново незачем.
      await pump(tester, _FakeApi(status: 'done', supplyId: 999));

      expect(find.text('Проверено'), findsNothing);
      expect(find.text('Черновик в UMAG'), findsOneWidget);
    },
  );

  testWidgets('на отправленной есть ссылка на черновик', (tester) async {
    await pump(tester, _FakeApi(supplyId: 999));

    expect(find.text('№999'), findsOneWidget);
    // Иконка «наружу» стоит дважды: в самой строке и на кнопке внизу. Строка
    // говорит, какой это черновик, кнопка — открывает его, не листая страницу.
    expect(find.byIcon(LucideIcons.external_link), findsNWidgets(2));
  });

  testWidgets('пока накладная не отправлена, ссылки нет', (tester) async {
    await pump(tester, _FakeApi());

    expect(find.byIcon(LucideIcons.external_link), findsNothing);
  });

  testWidgets('пока идёт разбор, действий не предлагаем', (tester) async {
    final api = _FakeApi(status: 'pending');

    await tester.pumpWidget(
      MaterialApp(
        home: DocumentDetailsPage(
          store: DocumentsStore(api: api),
          item: _item,
          umag: UmagAccountStore(api: api),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Проверено'), findsNothing);
    expect(find.text('Загрузить в UMAG'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('отказ от повторного разбора ничего не отправляет', (
    tester,
  ) async {
    final api = _FakeApi();
    await pump(tester, api);

    await tester.tap(find.byIcon(LucideIcons.scan_text));
    await tester.pumpAndSettle();

    expect(find.text('Распознать заново?'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(api.posts, isEmpty);
  });

  testWidgets('согласие перезапускает разбор', (tester) async {
    final api = _FakeApi();
    await pump(tester, api);

    await tester.tap(find.byIcon(LucideIcons.scan_text));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Распознать'));
    await tester.pumpAndSettle();

    expect(api.posts, ['/invoices/87/retry/']);
  });

  testWidgets('свайп по позиции спрашивает и удаляет её', (tester) async {
    final api = _FakeApi();
    await pump(tester, api);

    expect(find.text('Сырок Чудо'), findsOneWidget);

    await tester.drag(find.text('Сырок Чудо'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Удалить позицию?'), findsOneWidget);

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(api.deletes, ['/invoices/87/lines/765/']);
    expect(find.text('Сырок Чудо'), findsNothing);
    // Соседняя строка остаётся и получает первый номер — сервер перенумеровал.
    expect(find.text('Каша Агуша'), findsOneWidget);
  });

  testWidgets('отказ оставляет позицию на месте', (tester) async {
    final api = _FakeApi();
    await pump(tester, api);

    await tester.drag(find.text('Сырок Чудо'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(api.deletes, isEmpty);
    expect(find.text('Сырок Чудо'), findsOneWidget);
  });

  testWidgets('свайп вправо ничего не удаляет', (tester) async {
    final api = _FakeApi();
    await pump(tester, api);

    await tester.drag(find.text('Сырок Чудо'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Удалить позицию?'), findsNothing);
    expect(api.deletes, isEmpty);
  });

  testWidgets('сервер отказал — строка возвращается на экран', (tester) async {
    final api = _FakeApi()..refuseDelete = true;
    await pump(tester, api);

    await tester.drag(find.text('Сырок Чудо'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    expect(find.text('Позиция уже удалена'), findsOneWidget);

    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();

    // Свайп её увёл, но в базе она есть — значит должна вернуться.
    expect(find.text('Сырок Чудо'), findsOneWidget);
  });

  testWidgets('во время удаления кнопка действия остаётся на месте', (
    tester,
  ) async {
    // Сервер отвечает не сразу — иначе состояния «идёт удаление» не застать, и
    // проверка ничего не проверяет.
    final api = _FakeApi(status: 'done')..delay = const Duration(seconds: 1);
    await pump(tester, api);

    final before = tester.getTopLeft(find.text('Проверено'));

    await tester.drag(find.text('Сырок Чудо'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));

    // Смотрим на середине работы: раньше кнопка тут пропадала.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Проверено'),
      findsOneWidget,
      reason: 'кнопка пропала на время удаления',
    );
    expect(
      tester.getTopLeft(find.text('Проверено')),
      before,
      reason: 'кнопка сдвинулась',
    );

    await tester.pumpAndSettle();
  });

  testWidgets('ссылка на черновик не строится, пока магазины не приехали', (
    tester,
  ) async {
    // Кабинет не читали заранее — так бывает, если боковое меню ни разу не
    // открывали. Раньше в адрес уходил запасной «первый магазин», и человек
    // попадал в чужую приёмку.
    final api = _FakeApi(supplyId: 999);
    final umag = UmagAccountStore(api: api);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: DocumentDetailsPage(
          store: DocumentsStore(api: api),
          item: _item,
          umag: umag,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      umag.account.stores,
      isEmpty,
      reason: 'подготовка: список должен быть пуст',
    );

    await tester.tap(find.text('Черновик в UMAG'));
    await tester.pumpAndSettle();

    // Прежде чем собирать адрес, страница спросила кабинет.
    expect(
      api.umagAsked,
      greaterThan(0),
      reason: 'список магазинов не запросили',
    );
    expect(umag.account.stores.length, 3);
    expect(
      storeIndexOf(umag.account.stores, 17797),
      2,
      reason: 'магазин не тот',
    );
  });

  testWidgets('справочные значения прижаты к правому краю', (tester) async {
    await pump(tester, _FakeApi());

    final screen =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    // Номер и дата — подписи слева разной длины, значения должны кончаться на
    // одной вертикали, а не начинаться лесенкой.
    final number = tester.getBottomRight(find.text('KBH0425963'));
    final status = tester.getBottomRight(find.text('Проверено'));

    expect(
      number.dx,
      closeTo(status.dx, 1),
      reason: 'значения не выстроены по правому краю',
    );
    expect(
      number.dx,
      greaterThan(screen / 2),
      reason: 'значения остались слева',
    );
  });

  testWidgets('общую информацию можно свернуть и развернуть', (tester) async {
    await pump(tester, _FakeApi());

    // При открытии информация раскрыта: иначе тот, кто не знает про кнопку,
    // не увидит ни поставщика, ни статуса.
    expect(find.text('ПОСТАВЩИК'), findsOneWidget);
    expect(find.text('ОБРАБОТКА'), findsOneWidget);
    await tester.tap(find.text('ИНФОРМАЦИЯ'));
    await tester.pumpAndSettle();

    expect(find.text('ПОСТАВЩИК'), findsNothing);
    expect(find.text('ОБРАБОТКА'), findsNothing);
    // Подписи у переключателя нет — только стрелка.
    expect(find.text('свернуть'), findsNothing);
    expect(find.text('развернуть'), findsNothing);

    // Позиции и итог остаются: сворачивается только справочная часть.
    expect(find.text('ПОЗИЦИИ'), findsOneWidget);
    expect(find.text('Итого'), findsOneWidget);

    await tester.tap(find.text('ИНФОРМАЦИЯ'));
    await tester.pumpAndSettle();

    expect(find.text('ПОСТАВЩИК'), findsOneWidget);
  });

  testWidgets('свёрнутая информация освобождает место позициям', (
    tester,
  ) async {
    await pump(tester, _FakeApi());

    final before = tester.getTopLeft(find.text('ПОЗИЦИИ')).dy;

    await tester.tap(find.text('ИНФОРМАЦИЯ'));
    await tester.pumpAndSettle();

    final toggle = tester.getBottomLeft(find.text('ИНФОРМАЦИЯ')).dy;
    final lines = tester.getTopLeft(find.text('ПОЗИЦИИ')).dy;

    expect(lines, lessThan(before), reason: 'позиции не поднялись вверх');
    // И поднялись вплотную: пустая дыра на месте свёрнутой части — тот же
    // отъеденный экран, только без содержимого.
    expect(lines - toggle, lessThan(48), reason: 'осталась пустая дыра');
  });

  testWidgets('накладную из двух листов листают в просмотрщике', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeApi(
        images: ['http://server/media/1.jpg', 'http://server/media/2.jpg'],
      ),
    );

    await tester.tap(find.byTooltip('Открыть снимок'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoPage), findsOneWidget);
    // В шапке видно, какой лист открыт: иначе не понять, есть ли ещё.
    expect(find.text('1 из 2'), findsOneWidget);
  });

  testWidgets('у накладной из одного листа счётчика нет', (tester) async {
    await pump(tester, _FakeApi());

    await tester.tap(find.byTooltip('Открыть снимок'));
    await tester.pumpAndSettle();

    expect(find.byType(PhotoPage), findsOneWidget);
    expect(find.textContaining(' из '), findsNothing);
  });
}
