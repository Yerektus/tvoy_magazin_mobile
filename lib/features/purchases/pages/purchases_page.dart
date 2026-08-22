import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../shared/services/api_exception.dart';
import '../../../shared/widgets/error_dialog.dart';
import '../../../shared/widgets/message.dart';
import '../../documents/models/document.dart';
import '../models/plan.dart';
import '../services/plan_store.dart';
import 'plan_settings.dart';

/// План закупа: что заканчивается и сколько этого дозаказать.
///
/// Считает сервер по товарному отчёту UMAG. Здесь план читают и просят
/// пересчитать: ассортимент и остатки меняются каждый день, и вчерашний план
/// сегодня уже врёт.
class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key, required this.store, required this.drawer});

  final PlanStore store;
  final Widget drawer;

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onChanged);
    widget.store.load();
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Пересчёт: сперва спрашиваем период, потом считаем.
  Future<void> _rebuild() async {
    final plan = widget.store.plan;
    final chosen = await askPlanSettings(
      context,
      days: plan?.days ?? 30,
      horizon: plan?.horizon ?? 14,
    );

    if (chosen == null || !mounted) {
      return;
    }

    try {
      await widget.store.rebuild(days: chosen.days, horizon: chosen.horizon);
    } on ApiException catch (error) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Не удалось посчитать',
          message: error.message,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final plan = store.plan;

    return Scaffold(
      drawer: widget.drawer,
      appBar: AppBar(
        title: const Text('Закупки'),
        bottom: store.isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: RefreshIndicator(onRefresh: store.load, child: _body()),
      bottomNavigationBar: plan == null || plan.status != PlanStatus.ready
          ? null
          : _Total(plan: plan, onRebuild: store.isLoading ? null : _rebuild),
    );
  }

  Widget _body() {
    final store = widget.store;

    if (store.error != null) {
      return Message(
        icon: LucideIcons.cloud_off,
        title: 'Не удалось загрузить',
        note: store.error,
        onRetry: store.load,
      );
    }

    if (store.isLoading && store.plan == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // Расширение подключают в веб-кабинете, и только владелец с
    // администратором. Предлагать кнопку, которая всё равно откажет, незачем.
    if (!store.isConnected) {
      return const Message(
        icon: LucideIcons.shopping_cart,
        title: 'Планирование не подключено',
        note: 'Включите расширение «Планирование закупов» в веб-кабинете',
      );
    }

    final plan = store.plan;

    if (plan == null) {
      return Message(
        icon: LucideIcons.shopping_cart,
        title: 'Плана ещё нет',
        note: 'Посчитаем, что заканчивается, по продажам из UMAG',
        onRetry: _rebuild,
        retryLabel: 'Посчитать',
      );
    }

    if (plan.status == PlanStatus.failed) {
      return Message(
        icon: LucideIcons.circle_alert,
        title: 'Не удалось посчитать',
        note: plan.error.isEmpty ? null : plan.error,
        onRetry: _rebuild,
        retryLabel: 'Посчитать заново',
      );
    }

    if (plan.status == PlanStatus.building) {
      return const Center(child: CircularProgressIndicator());
    }

    if (plan.items.isEmpty) {
      return Message(
        icon: LucideIcons.circle_check,
        title: 'Закупать нечего',
        note: 'Остатков хватает на ${plan.horizon} дней вперёд',
        onRetry: _rebuild,
        retryLabel: 'Посчитать заново',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: plan.items.length + 1,
      itemBuilder: (_, index) => index == 0
          ? _Header(plan: plan)
          : _ItemTile(item: plan.items[index - 1]),
    );
  }
}

/// Что и за какой период посчитано.
class _Header extends StatelessWidget {
  const _Header({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F0F0),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ПРОДАЖИ ЗА ${plan.days} ДН. · ЗАКУП НА ${plan.horizon} ДН.',
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
              color: Color(0xFF737373),
            ),
          ),
          if (plan.builtAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Посчитан ${formatDateTime(plan.builtAt!)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFFA3A3A3)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Строка плана: товар, сколько заказать и на сколько хватит остатка.
class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item});

  final PlanItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Главное число строки — сколько заказать.
              Text(
                '${formatQuantity(item.suggested)} ${item.measure}'.trim(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    formatCover(item.coverDays),
                    if (item.supplier.isNotEmpty) item.supplier,
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    // Остатка меньше чем на три дня — про это стоит знать сразу.
                    color: (item.coverDays ?? 99) < 3
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF737373),
                  ),
                ),
              ),
              if (item.cost != null)
                Text(
                  formatMoney(item.cost),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF737373),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Нижняя панель: сколько всего закупать и кнопка пересчёта.
class _Total extends StatelessWidget {
  const _Total({required this.plan, required this.onRebuild});

  final Plan plan;
  final VoidCallback? onRebuild;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E5E5))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Позиций: ${plan.itemsTotal}',
                    style: const TextStyle(color: Color(0xFF737373)),
                  ),
                  Text(
                    formatMoney(plan.totalCost),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRebuild,
                icon: const Icon(LucideIcons.refresh_cw, size: 18),
                label: const Text('Посчитать заново'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
