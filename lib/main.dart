import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'data/expense_repository.dart';
import 'domain/expense.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  runApp(const ControleGastosApp());
}

class ControleGastosApp extends StatelessWidget {
  const ControleGastosApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Meu controle',
    debugShowCheckedModeBanner: false,
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF176B58),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F7F5),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF5F6F4),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    home: const ExpenseHome(),
  );
}

typedef MyApp = ControleGastosApp;

class ExpenseHome extends StatefulWidget {
  const ExpenseHome({super.key});
  @override
  State<ExpenseHome> createState() => _ExpenseHomeState();
}

class _ExpenseHomeState extends State<ExpenseHome> {
  final _repository = ExpenseRepository();
  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
  List<Expense> _expenses = [];
  bool _loading = true;
  int _page = 0;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final expenses = await _repository.load();
    if (!mounted) return;
    setState(() {
      _expenses = expenses;
      _loading = false;
    });
  }

  List<Expense> get _monthExpenses => _expenses
      .where(
        (expense) =>
            expense.spentAt.year == _month.year &&
            expense.spentAt.month == _month.month,
      )
      .toList();

  int get _monthTotal =>
      _monthExpenses.fold(0, (sum, expense) => sum + expense.amountCents);

  Future<void> _persist(List<Expense> next) async {
    next.sort((a, b) => b.spentAt.compareTo(a.spentAt));
    await _repository.saveAll(next);
    if (mounted) setState(() => _expenses = next);
  }

  Future<void> _openExpense({Expense? expense}) async {
    final result = await showDialog<Expense>(
      context: context,
      builder: (_) => ExpenseDialog(expense: expense, currency: _currency),
    );
    if (result == null) return;
    final next = [..._expenses];
    final index = next.indexWhere((item) => item.id == result.id);
    if (index < 0) {
      next.add(result);
    } else {
      next[index] = result;
    }
    await _persist(next);
  }

  Future<void> _deleteExpense(Expense expense) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir despesa?'),
        content: Text(
          '“${expense.description}” será removida do seu histórico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (remove == true)
      await _persist(_expenses.where((item) => item.id != expense.id).toList());
  }

  void _changeMonth(int amount) => setState(() {
    _month = DateTime(_month.year, _month.month + amount);
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final pages = [_overview(), _expenseList(), _reports()];
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide) _sideNavigation(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1060),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            wide ? 32 : 20,
                            24,
                            wide ? 32 : 20,
                            12,
                          ),
                          child: pages[_page],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: (index) => setState(() => _page = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view),
                  label: 'Início',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'Despesas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: 'Relatórios',
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExpense(),
        icon: const Icon(Icons.add),
        label: const Text('Nova despesa'),
      ),
    );
  }

  Widget _sideNavigation() => NavigationRail(
    selectedIndex: _page,
    onDestinationSelected: (index) => setState(() => _page = index),
    labelType: NavigationRailLabelType.all,
    leading: Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 28),
      child: Icon(
        Icons.savings_outlined,
        size: 30,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
    destinations: const [
      NavigationRailDestination(
        icon: Icon(Icons.grid_view_outlined),
        selectedIcon: Icon(Icons.grid_view),
        label: Text('Início'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: Text('Despesas'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.bar_chart_outlined),
        selectedIcon: Icon(Icons.bar_chart),
        label: Text('Relatórios'),
      ),
    ],
  );

  Widget _overview() {
    final latest = [..._monthExpenses]
      ..sort((a, b) => b.spentAt.compareTo(a.spentAt));
    return ListView(
      children: [
        _pageHeader(
          'Seu dinheiro,\nmais claro.',
          'Acompanhe seus gastos com tranquilidade.',
        ),
        const SizedBox(height: 20),
        _monthSelector(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total de despesas',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                Text(
                  _currency.format(_monthTotal / 100),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_monthExpenses.length} ${_monthExpenses.length == 1 ? 'lançamento' : 'lançamentos'} neste mês',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(value: 1, minHeight: 8),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeading(
          'Despesas recentes',
          action: 'Ver todas',
          onAction: () => setState(() => _page = 1),
        ),
        const SizedBox(height: 8),
        if (latest.isEmpty)
          _emptyState(
            'Nenhuma despesa neste mês',
            'Adicione seu primeiro gasto para começar a acompanhar.',
          ),
        ...latest.take(5).map((expense) => _expenseTile(expense)),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _expenseList() {
    final entries =
        _monthExpenses
            .where(
              (expense) =>
                  _categoryFilter == null ||
                  expense.categoryId == _categoryFilter,
            )
            .toList()
          ..sort((a, b) => b.spentAt.compareTo(a.spentAt));
    return ListView(
      children: [
        _pageHeader('Despesas', 'Todos os lançamentos do mês selecionado.'),
        const SizedBox(height: 16),
        _monthSelector(),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _categoryFilter,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.filter_list),
            labelText: 'Filtrar por categoria',
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Todas as categorias'),
            ),
            ...expenseCategories.map(
              (category) => DropdownMenuItem<String?>(
                value: category.id,
                child: Text(category.label),
              ),
            ),
          ],
          onChanged: (value) => setState(() => _categoryFilter = value),
        ),
        const SizedBox(height: 16),
        if (entries.isEmpty)
          _emptyState(
            'Nada por aqui',
            'Tente outro filtro ou adicione uma despesa.',
          ),
        ...entries.map((expense) => _expenseTile(expense, actions: true)),
        const SizedBox(height: 84),
      ],
    );
  }

  Widget _reports() {
    final totals = <String, int>{};
    for (final expense in _monthExpenses) {
      totals.update(
        expense.categoryId,
        (value) => value + expense.amountCents,
        ifAbsent: () => expense.amountCents,
      );
    }
    final ordered = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ListView(
      children: [
        _pageHeader('Relatórios', 'Veja para onde está indo seu dinheiro.'),
        const SizedBox(height: 16),
        _monthSelector(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gastos por categoria',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  _currency.format(_monthTotal / 100),
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 20),
                if (ordered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Sem despesas para este mês')),
                  ),
                ...ordered.map((entry) {
                  final category = categoryFor(entry.key);
                  final ratio = _monthTotal == 0
                      ? 0.0
                      : entry.value / _monthTotal;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _categoryIcon(category, size: 34),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                category.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              _currency.format(entry.value / 100),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 7,
                            color: Color(category.colorValue),
                            backgroundColor: const Color(0xFFF0F1EF),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _pageHeader(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 30,
            height: 1.12,
            fontWeight: FontWeight.w700,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
        ),
      ],
    ),
  );

  Widget _monthSelector() => Row(
    children: [
      IconButton.filledTonal(
        onPressed: () => _changeMonth(-1),
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: Center(
          child: Text(
            DateFormat('MMMM yyyy', 'pt_BR').format(_month),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      IconButton.filledTonal(
        onPressed: () => _changeMonth(1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  Widget _sectionHeading(
    String title, {
    String? action,
    VoidCallback? onAction,
  }) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      if (action != null) TextButton(onPressed: onAction, child: Text(action)),
    ],
  );

  Widget _emptyState(String title, String message) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 34,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    ),
  );

  Widget _expenseTile(Expense expense, {bool actions = false}) {
    final category = categoryFor(expense.categoryId);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: _categoryIcon(category),
        title: Text(
          expense.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${category.label} · ${_dateFormat.format(expense.spentAt)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currency.format(expense.amountCents / 100),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (actions)
              PopupMenuButton<String>(
                onSelected: (value) => value == 'edit'
                    ? _openExpense(expense: expense)
                    : _deleteExpense(expense),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'delete', child: Text('Excluir')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _categoryIcon(ExpenseCategory category, {double size = 42}) =>
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Color(category.colorValue).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(size * .35),
        ),
        child: Icon(
          _iconFor(category.icon),
          color: Color(category.colorValue),
          size: size * .48,
        ),
      );

  IconData _iconFor(String name) => switch (name) {
    'restaurant' => Icons.restaurant,
    'home' => Icons.home_outlined,
    'directions_car' => Icons.directions_car_outlined,
    'favorite' => Icons.favorite_border,
    'movie' => Icons.movie_outlined,
    'shopping_bag' => Icons.shopping_bag_outlined,
    'receipt_long' => Icons.receipt_long_outlined,
    _ => Icons.more_horiz,
  };
}

class ExpenseDialog extends StatefulWidget {
  const ExpenseDialog({super.key, this.expense, required this.currency});
  final Expense? expense;
  final NumberFormat currency;

  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late DateTime _date;
  late String _category;
  bool _manualCategory = false;
  bool _didChooseCategory = false;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    _description = TextEditingController(text: expense?.description ?? '');
    _amount = TextEditingController(
      text: expense == null
          ? ''
          : (expense.amountCents / 100).toStringAsFixed(2).replaceAll('.', ','),
    );
    _date = expense?.spentAt ?? DateTime.now();
    _category = expense?.categoryId ?? 'other';
    _manualCategory =
        expense?.categorizationMethod == CategorizationMethod.manual;
    _didChooseCategory = false;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _descriptionChanged(String value) {
    if (_manualCategory || _didChooseCategory) return;
    final suggested = suggestCategory(value);
    if (suggested != null) setState(() => _category = suggested);
  }

  int? _parseCents(String value) {
    final normalized = value
        .trim()
        .replaceAll('R\$', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    final amount = double.tryParse(normalized);
    if (amount == null || amount <= 0 || amount > 999999999) return null;
    return (amount * 100).round();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.expense == null ? 'Nova despesa' : 'Editar despesa'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor',
                  prefixText: 'R\$  ',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) => _parseCents(value ?? '') == null
                    ? 'Informe um valor maior que zero'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                onChanged: _descriptionChanged,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  hintText: 'Ex.: mercado, almoço…',
                  prefixIcon: Icon(Icons.notes),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Informe uma descrição'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Categoria',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: expenseCategories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Text(category.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _category = value ?? 'other';
                  _manualCategory = true;
                  _didChooseCategory = true;
                }),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Data da despesa'),
                subtitle: Text(DateFormat('dd/MM/yyyy', 'pt_BR').format(_date)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 366)),
                    locale: const Locale('pt', 'BR'),
                  );
                  if (selected != null) setState(() => _date = selected);
                },
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _save, child: const Text('Salvar despesa')),
    ],
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final previous = widget.expense;
    Navigator.pop(
      context,
      Expense(
        id: previous?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        amountCents: _parseCents(_amount.text)!,
        description: _description.text.trim(),
        categoryId: _category,
        spentAt: _date,
        source: previous?.source ?? ExpenseSource.manual,
        categorizationMethod: _manualCategory || _didChooseCategory
            ? CategorizationMethod.manual
            : CategorizationMethod.automatic,
      ),
    );
  }
}
