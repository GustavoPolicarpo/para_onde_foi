import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:file_selector/file_selector.dart';
import 'package:file_saver/file_saver.dart';

import 'data/expense_repository.dart';
import 'domain/expense.dart';

const _widgetChannel = MethodChannel('gasto_claro/widget');
final _expenseHomeKey = GlobalKey<_ExpenseHomeState>();

const _categoryIconOptions = <(String, String, IconData)>[
  ('restaurant', 'Restaurante', Icons.restaurant_outlined),
  ('local_grocery_store', 'Mercado', Icons.local_grocery_store_outlined),
  ('bakery_dining', 'Padaria', Icons.bakery_dining_outlined),
  ('fastfood', 'Lanche', Icons.fastfood_outlined),
  ('home', 'Casa', Icons.home_outlined),
  ('apartment', 'Apartamento', Icons.apartment_outlined),
  ('lightbulb', 'Energia', Icons.lightbulb_outline),
  ('water_drop', 'Água', Icons.water_drop_outlined),
  ('directions_car', 'Carro', Icons.directions_car_outlined),
  ('train', 'Transporte público', Icons.train_outlined),
  ('local_gas_station', 'Combustível', Icons.local_gas_station_outlined),
  ('medical_services', 'Saúde', Icons.medical_services_outlined),
  ('favorite', 'Saúde', Icons.favorite_outline),
  ('fitness_center', 'Exercícios', Icons.fitness_center),
  ('movie', 'Cinema', Icons.movie_outlined),
  ('sports_soccer', 'Esportes', Icons.sports_soccer_outlined),
  ('shopping_bag', 'Compras', Icons.shopping_bag_outlined),
  ('checkroom', 'Roupas', Icons.checkroom_outlined),
  ('receipt_long', 'Contas', Icons.receipt_long_outlined),
  ('payments', 'Pagamentos', Icons.payments_outlined),
  ('pets', 'Pets', Icons.pets_outlined),
  ('school', 'Educação', Icons.school_outlined),
  ('flight', 'Viagem', Icons.flight_outlined),
  ('wifi', 'Internet', Icons.wifi),
  ('phone_android', 'Celular', Icons.phone_android),
  ('work', 'Trabalho', Icons.work_outline),
  ('card_giftcard', 'Presentes', Icons.card_giftcard),
  ('more_horiz', 'Outros', Icons.more_horiz),
];

IconData _categoryIconData(String name) => _categoryIconOptions
    .firstWhere(
      (option) => option.$1 == name,
      orElse: () => _categoryIconOptions.last,
    )
    .$3;

Future<void> _syncWidgetSummary(
  List<Expense> expenses,
  Map<String, int> budgets,
  List<ExpenseCategory> categories,
  NumberFormat currency,
) async {
  final now = DateTime.now();
  final currentMonth = DateTime(now.year, now.month);
  final earliestExpense = expenses.isEmpty
      ? currentMonth
      : expenses
            .map((entry) => DateTime(entry.spentAt.year, entry.spentAt.month))
            .reduce((a, b) => a.isBefore(b) ? a : b);
  final startMonth = earliestExpense.isAfter(currentMonth)
      ? currentMonth
      : earliestExpense;
  final months = <Map<String, Object?>>[];
  for (
    var month = startMonth;
    !month.isAfter(currentMonth);
    month = DateTime(month.year, month.month + 1)
  ) {
    final monthExpenses = expenses.where(
      (entry) => entry.spentAt.year == month.year && entry.spentAt.month == month.month,
    );
    final totalCents = monthExpenses.fold<int>(
      0,
      (sum, entry) => sum + entry.amountCents,
    );
    final spentByCategory = <String, int>{};
    for (final entry in monthExpenses) {
      spentByCategory.update(
        entry.categoryId,
        (spent) => spent + entry.amountCents,
        ifAbsent: () => entry.amountCents,
      );
    }
    final budgetRows = categories.map((category) {
      final spent = spentByCategory[category.id] ?? 0;
      final limit = budgets[category.id];
      return {
        'label': category.label,
        'spent': currency.format(spent / 100),
        'limit': limit == null ? 'Sem limite' : currency.format(limit / 100),
        'hasLimit': limit != null && limit > 0,
        'progress': limit == null || limit == 0
            ? 0
            : ((spent * 100) ~/ limit).clamp(0, 100),
        'over': limit != null && spent > limit,
      };
    }).toList();
    months.add({
      'key': DateFormat('yyyy-MM').format(month),
      'label': DateFormat('MMM/yy', 'pt_BR').format(month).toUpperCase(),
      'amount': currency.format(totalCents / 100),
      'current': month.year == currentMonth.year &&
          month.month == currentMonth.month,
      'budgets': budgetRows,
    });
  }
  try {
    await _widgetChannel.invokeMethod<void>('updateWidgetSummary', {
      'months': jsonEncode(months),
    });
  } on MissingPluginException {
    // Web and non-Android builds don't have the Android home widget.
  } on PlatformException {
    // Keep app saves independent from widget refresh failures.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  final initialQuickEntry = await _widgetChannel
      .invokeMethod<bool>('getInitialQuickEntry')
      .catchError((_) => false);
  if (initialQuickEntry != true) {
    runApp(const GastoClaroApp());
  } else {
    runApp(const QuickEntryApp());
  }
}

class GastoClaroApp extends StatefulWidget {
  const GastoClaroApp({super.key});

  @override
  State<GastoClaroApp> createState() => _GastoClaroAppState();
}

class _GastoClaroAppState extends State<GastoClaroApp> {
  @override
  void initState() {
    super.initState();
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'openEntry') {
        _expenseHomeKey.currentState?._openExpense();
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'GastoClaro',
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
    home: ExpenseHome(key: _expenseHomeKey),
  );
}

typedef MyApp = GastoClaroApp;

class QuickEntryApp extends StatelessWidget {
  const QuickEntryApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Novo lançamento',
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
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B58)),
      scaffoldBackgroundColor: Colors.transparent,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF5F6F4),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    home: const QuickEntryHost(),
  );
}

class QuickEntryHost extends StatefulWidget {
  const QuickEntryHost({super.key});

  @override
  State<QuickEntryHost> createState() => _QuickEntryHostState();
}

class _QuickEntryHostState extends State<QuickEntryHost> {
  final _repository = ExpenseRepository();
  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  List<ExpenseCategory> _categories = expenseCategories;
  List<Expense> _history = [];
  List<String> _tags = [];
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    await _applyDueRecurringExpenses(_repository);
    final customCategories = await _repository.loadCategories();
    final tags = await _repository.loadTags();
    final history = await _repository.load();
    final categoryMap = {
      for (final category in expenseCategories) category.id: category,
      for (final category in customCategories) category.id: category,
    };
    if (!mounted) return;
    setState(() {
      _categories = categoryMap.values.toList();
      _history = history;
      _tags = tags;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _openForm());
  }

  Future<void> _openForm() async {
    if (_opened || !mounted) return;
    _opened = true;
    final result = await showDialog<ExpenseFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExpenseDialog(
        quickEntry: true,
        currency: _currency,
        categories: _categories,
        knownTags: _tags,
        history: _history,
      ),
    );
    if (!mounted) return;
    if (result == null) {
      await _widgetChannel.invokeMethod<void>('finishQuickEntry', false);
      return;
    }
    try {
      final quickEntry = result.expense.copyWith(spentAt: DateTime.now());
      final entries = await _repository.load();
      entries.add(quickEntry);
      entries.sort((a, b) => b.spentAt.compareTo(a.spentAt));
      await _repository.saveAll(entries);
      await _repository.saveTags({..._tags, ...quickEntry.tags}.toList());
      if (result.recurringRule != null) {
        final rules = await _repository.loadRecurringRules();
        await _repository.saveRecurringRules([...rules, result.recurringRule!]);
      }
      final budgets = await _repository.loadBudgets();
      await _syncWidgetSummary(entries, budgets, _categories, _currency);
      await _widgetChannel.invokeMethod<void>('finishQuickEntry', true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível salvar o lançamento.'),
          ),
        );
      }
      _opened = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openForm());
    }
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class ExpenseHome extends StatefulWidget {
  const ExpenseHome({super.key});
  @override
  State<ExpenseHome> createState() => _ExpenseHomeState();
}

class _ExpenseHomeState extends State<ExpenseHome> with WidgetsBindingObserver {
  final _repository = ExpenseRepository();
  final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFormat = DateFormat('dd/MM/yyyy', 'pt_BR');
  List<Expense> _expenses = [];
  List<ExpenseCategory> _categories = expenseCategories;
  Map<String, int> _budgets = {};
  List<RecurringRule> _recurringRules = [];
  List<String> _tags = [];
  final _searchController = TextEditingController();
  DateTimeRange? _dateRange;
  final Set<String> _movementTagFilters = {};
  final Set<String> _reportTagFilters = {};
  bool _reportGroupByTags = false;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _loading = true;
  bool _refreshInProgress = false;
  int _page = 0;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    try {
      await _applyDueRecurringExpenses(_repository);
      final expenses = await _repository.load();
      final customCategories = await _repository.loadCategories();
      final budgets = await _repository.loadBudgets();
      final recurringRules = await _repository.loadRecurringRules();
      final storedTags = await _repository.loadTags();
      final categoryMap = {
        for (final category in expenseCategories) category.id: category,
      };
      for (final category in customCategories) {
        categoryMap[category.id] = category;
      }
      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _categories = categoryMap.values.toList();
        _budgets = budgets;
        _recurringRules = recurringRules;
        _tags = storedTags;
        final now = DateTime.now();
        if (_month.year != now.year || _month.month != now.month) {
          _month = DateTime(now.year, now.month);
        }
        _loading = false;
      });
      await _syncWidgetSummary(
        expenses,
        budgets,
        categoryMap.values.toList(),
        _currency,
      );
    } finally {
      _refreshInProgress = false;
    }
  }

  List<Expense> get _monthExpenses => _expenses
      .where(
        (expense) =>
            expense.spentAt.year == _month.year &&
            expense.spentAt.month == _month.month,
      )
      .toList();

  int get _monthExpensesTotal =>
      _monthExpenses.fold(0, (sum, entry) => sum + entry.amountCents);

  Future<void> _persist(List<Expense> next) async {
    next.sort((a, b) => b.spentAt.compareTo(a.spentAt));
    await _repository.saveAll(next);
    if (mounted) setState(() => _expenses = next);
    await _syncWidgetSummary(next, _budgets, _categories, _currency);
  }

  Future<void> _persistCategories(List<ExpenseCategory> next) async {
    await _repository.saveCategories(
      next.where((category) => category.isCustom).toList(),
    );
    if (mounted) {
      final categoryMap = {
        for (final category in expenseCategories) category.id: category,
      };
      for (final category in next.where((category) => category.isCustom)) {
        categoryMap[category.id] = category;
      }
      setState(() => _categories = categoryMap.values.toList());
    }
  }

  Future<void> _persistBudgets(Map<String, int> next) async {
    await _repository.saveBudgets(next);
    if (mounted) setState(() => _budgets = next);
    await _syncWidgetSummary(_expenses, next, _categories, _currency);
  }

  Future<void> _persistRecurring(List<RecurringRule> next) async {
    await _repository.saveRecurringRules(next);
    if (mounted) setState(() => _recurringRules = next);
  }

  Future<void> _openExpense({Expense? expense}) async {
    final result = await showDialog<ExpenseFormResult>(
      context: context,
      builder: (_) => ExpenseDialog(
        expense: expense,
        currency: _currency,
        categories: _categories,
        knownTags: _tags,
        history: _expenses,
      ),
    );
    if (result == null) return;
    final savedExpense = result.expense;
    final next = [..._expenses];
    final index = next.indexWhere((item) => item.id == savedExpense.id);
    if (index < 0) {
      next.add(savedExpense);
    } else {
      next[index] = savedExpense;
    }
    if (result.recurringRule != null) {
      await _persistRecurring([..._recurringRules, result.recurringRule!]);
    }
    final nextTags = {..._tags, ...savedExpense.tags}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    next.sort((a, b) => b.spentAt.compareTo(a.spentAt));
    await _repository.saveTags(nextTags);
    await _repository.saveAll(next);
    if (mounted) {
      setState(() {
        _tags = nextTags;
        _expenses = next;
      });
    }
    await _syncWidgetSummary(next, _budgets, _categories, _currency);
  }

  Future<void> _persistTags(List<String> next) async {
    final clean =
        next
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await _repository.saveTags(clean);
    if (mounted)
      setState(() {
        _tags = clean;
        _movementTagFilters.removeWhere((tag) => !clean.contains(tag));
        _reportTagFilters.removeWhere((tag) => !clean.contains(tag));
      });
  }

  Future<void> _deleteExpense(Expense expense) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir lançamento?'),
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
    if (remove == true) {
      await _persist(_expenses.where((item) => item.id != expense.id).toList());
    }
  }

  Future<void> _bulkChangeCategory() async {
    final categoryId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Definir categoria'),
        children: _categories
            .where((category) => !category.archived)
            .map(
              (category) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, category.id),
                child: Text(category.label),
              ),
            )
            .toList(),
      ),
    );
    if (categoryId == null || _selectedIds.isEmpty) return;
    await _persist(
      _expenses
          .map(
            (entry) => _selectedIds.contains(entry.id)
                ? entry.copyWith(
                    categoryId: categoryId,
                    categorySetAt: DateTime.now(),
                    categorizationMethod: CategorizationMethod.manual,
                  )
                : entry,
          )
          .toList(),
    );
    _endSelection();
  }

  Future<void> _bulkAddTag() async {
    if (_selectedIds.isEmpty) return;
    final tag = await showDialog<String>(
      context: context,
      builder: (_) => const TagInputDialog(),
    );
    if (tag == null) return;
    await _persistTags([..._tags, tag]);
    await _persist(
      _expenses.map((entry) {
        if (!_selectedIds.contains(entry.id)) return entry;
        return entry.copyWith(tags: {...entry.tags, tag}.toList());
      }).toList(),
    );
    _endSelection();
  }

  Future<void> _bulkRemoveTag() async {
    if (_selectedIds.isEmpty) return;
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Remover tag dos selecionados'),
        children: _tags
            .map(
              (tag) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, tag),
                child: Text(tag),
              ),
            )
            .toList(),
      ),
    );
    if (tag == null) return;
    await _persist(
      _expenses
          .map(
            (entry) => _selectedIds.contains(entry.id)
                ? entry.copyWith(
                    tags: entry.tags.where((item) => item != tag).toList(),
                  )
                : entry,
          )
          .toList(),
    );
    _endSelection();
  }

  void _endSelection() => setState(() {
    _selectionMode = false;
    _selectedIds.clear();
  });

  void _changeMonth(int amount) => setState(() {
    _month = DateTime(_month.year, _month.month + amount);
  });

  Future<void> _chooseDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _dateRange,
    );
    if (range != null) setState(() => _dateRange = range);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final pages = [
      _overview(),
      _expenseList(),
      _budgetPage(),
      _reports(),
      _toolsPage(),
    ];
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
                  label: 'Movimentos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet),
                  label: 'Orçamento',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: 'Relatórios',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: 'Mais',
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openExpense(),
        icon: const Icon(Icons.add),
        label: const Text('Novo lançamento'),
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
        label: Text('Movimentos'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet),
        label: Text('Orçamento'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.bar_chart_outlined),
        selectedIcon: Icon(Icons.bar_chart),
        label: Text('Relatórios'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.tune_outlined),
        selectedIcon: Icon(Icons.tune),
        label: Text('Mais'),
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
                  'Despesas do mês',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                Text(
                  _currency.format(_monthExpensesTotal / 100),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_monthExpenses.length} despesas registradas neste mês',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeading(
          'Movimentos recentes',
          action: 'Ver todos',
          onAction: () => setState(() => _page = 1),
        ),
        const SizedBox(height: 8),
        if (latest.isEmpty)
          _emptyState(
            'Nenhum movimento neste mês',
            'Registre sua primeira despesa para acompanhar o mês.',
          ),
        ...latest.take(5).map((expense) => _expenseTile(expense)),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _expenseList() {
    final entries =
        (_dateRange == null ? _monthExpenses : _expenses)
            .where(
              (expense) =>
                  (_categoryFilter == null ||
                      expense.categoryId == _categoryFilter) &&
                  ('${expense.description} ${expense.notes ?? ''} ${expense.tags.join(' ')}')
                      .toLowerCase()
                      .contains(_searchController.text.trim().toLowerCase()) &&
                  _movementTagFilters.every(expense.tags.contains) &&
                  (_dateRange == null ||
                      (!expense.spentAt.isBefore(
                            DateTime(
                              _dateRange!.start.year,
                              _dateRange!.start.month,
                              _dateRange!.start.day,
                            ),
                          ) &&
                          !expense.spentAt.isAfter(
                            DateTime(
                              _dateRange!.end.year,
                              _dateRange!.end.month,
                              _dateRange!.end.day,
                              23,
                              59,
                              59,
                            ),
                          ))),
            )
            .toList()
          ..sort((a, b) => b.spentAt.compareTo(a.spentAt));
    return ListView(
      children: [
        Row(
          children: [
            Expanded(
              child: _pageHeader(
                'Movimentos',
                'Despesas do período selecionado.',
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _selectionMode = !_selectionMode;
                _selectedIds.clear();
              }),
              child: Text(_selectionMode ? 'Cancelar' : 'Selecionar'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_dateRange == null)
          _monthSelector()
        else
          Row(
            children: [
              Expanded(
                child: Text(
                  'Intervalo: ${DateFormat('dd/MM/yyyy').format(_dateRange!.start)} – ${DateFormat('dd/MM/yyyy').format(_dateRange!.end)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _dateRange = null),
                icon: const Icon(Icons.close),
                tooltip: 'Limpar intervalo',
              ),
            ],
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Buscar descrição',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
              icon: const Icon(Icons.close),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _chooseDateRange,
              icon: const Icon(Icons.date_range),
              label: Text(
                _dateRange == null
                    ? 'Período'
                    : '${DateFormat('dd/MM').format(_dateRange!.start)}–${DateFormat('dd/MM').format(_dateRange!.end)}',
              ),
            ),
            if (_dateRange != null)
              IconButton(
                onPressed: () => setState(() => _dateRange = null),
                icon: const Icon(Icons.clear),
              ),
          ],
        ),
        const SizedBox(height: 10),
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
            ..._categories
                .where((category) => !category.archived)
                .map(
                  (category) => DropdownMenuItem<String?>(
                    value: category.id,
                    child: Text(category.label),
                  ),
                ),
          ],
          onChanged: (value) => setState(() => _categoryFilter = value),
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Filtrar pelas tags'),
          Wrap(
            spacing: 6,
            children: _tags
                .map(
                  (tag) => FilterChip(
                    label: Text(tag),
                    selected: _movementTagFilters.contains(tag),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _movementTagFilters.add(tag);
                      } else {
                        _movementTagFilters.remove(tag);
                      }
                    }),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 12),
        if (_selectionMode)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_selectedIds.length} selecionado(s)'),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() {
                          final visibleIds = entries
                              .map((entry) => entry.id)
                              .toSet();
                          if (visibleIds.isNotEmpty &&
                              visibleIds.every(_selectedIds.contains)) {
                            _selectedIds.removeAll(visibleIds);
                          } else {
                            _selectedIds.addAll(visibleIds);
                          }
                        }),
                        icon: const Icon(Icons.select_all),
                        label: const Text('Visíveis'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : _bulkChangeCategory,
                        icon: const Icon(Icons.category_outlined),
                        label: const Text('Categoria'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _selectedIds.isEmpty ? null : _bulkAddTag,
                        icon: const Icon(Icons.sell_outlined),
                        label: const Text('Adicionar tag'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _selectedIds.isEmpty || _tags.isEmpty
                            ? null
                            : _bulkRemoveTag,
                        icon: const Icon(Icons.remove_circle_outline),
                        label: const Text('Remover tag'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (entries.isEmpty)
          _emptyState(
            'Nada por aqui',
            'Tente outro filtro ou adicione uma despesa.',
          ),
        ...entries.map(
          (expense) => _expenseTile(
            expense,
            actions: !_selectionMode,
            selectionMode: _selectionMode,
            selected: _selectedIds.contains(expense.id),
            onSelect: () => setState(() {
              if (!_selectedIds.add(expense.id))
                _selectedIds.remove(expense.id);
            }),
          ),
        ),
        const SizedBox(height: 84),
      ],
    );
  }

  Widget _reports() {
    final totals = <String, int>{};
    final reportEntries = _monthExpenses.where(
      (entry) => _reportTagFilters.every(entry.tags.contains),
    );
    for (final expense in reportEntries) {
      final groupKey = _reportGroupByTags
          ? (expense.tags.isEmpty
                ? 'Sem tags'
                : (expense.tags.toList()..sort()).join(' + '))
          : expense.categoryId;
      totals.update(
        groupKey,
        (value) => value + expense.amountCents,
        ifAbsent: () => expense.amountCents,
      );
    }
    final ordered = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final filteredTotal = reportEntries.fold<int>(
      0,
      (sum, entry) => sum + entry.amountCents,
    );
    return ListView(
      children: [
        _pageHeader('Relatórios', 'Veja para onde está indo seu dinheiro.'),
        const SizedBox(height: 16),
        _monthSelector(),
        const SizedBox(height: 12),
        DropdownButtonFormField<bool>(
          initialValue: _reportGroupByTags,
          decoration: const InputDecoration(labelText: 'Agrupar por'),
          items: const [
            DropdownMenuItem(value: false, child: Text('Categoria')),
            DropdownMenuItem(value: true, child: Text('Combinação de tags')),
          ],
          onChanged: (value) =>
              setState(() => _reportGroupByTags = value ?? false),
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Combinar filtros de tags (todos os selecionados)'),
          Wrap(
            spacing: 6,
            children: _tags
                .map(
                  (tag) => FilterChip(
                    label: Text(tag),
                    selected: _reportTagFilters.contains(tag),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _reportTagFilters.add(tag);
                      } else {
                        _reportTagFilters.remove(tag);
                      }
                    }),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _reportGroupByTags
                      ? 'Gastos por combinação de tags'
                      : 'Gastos por categoria',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  _currency.format(filteredTotal / 100),
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 20),
                if (ordered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Sem despesas para este mês')),
                  ),
                ...ordered.map((entry) {
                  final category = !_reportGroupByTags
                      ? categoryFor(entry.key, _categories)
                      : null;
                  final budgetLimit =
                      category == null ? null : _budgets[category.id];
                  final budgetSpent = category == null
                      ? 0
                      : _monthExpenses
                            .where((item) => item.categoryId == category.id)
                            .fold<int>(0, (sum, item) => sum + item.amountCents);
                  final budgetRatio = budgetLimit == null || budgetLimit == 0
                      ? null
                      : budgetSpent / budgetLimit;
                  final ratio = filteredTotal == 0
                      ? 0.0
                      : entry.value / filteredTotal;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            if (category != null)
                              _categoryIcon(category, size: 34)
                            else
                              const CircleAvatar(
                                radius: 17,
                                child: Icon(Icons.sell_outlined, size: 17),
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                category?.label ?? entry.key,
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
                        if (budgetLimit != null && budgetRatio != null) ...[
                          const SizedBox(height: 5),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Orçamento ${_currency.format(budgetLimit / 100)} · '
                              '${_currency.format(budgetSpent / 100)} usado · '
                              '${(budgetRatio * 100).round()}%',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                        const SizedBox(height: 9),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 7,
                            color: category == null
                                ? Theme.of(context).colorScheme.primary
                                : Color(category.colorValue),
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

  Widget _budgetPage() {
    final expenseByCategory = <String, int>{};
    for (final entry in _monthExpenses) {
      expenseByCategory.update(
        entry.categoryId,
        (value) => value + entry.amountCents,
        ifAbsent: () => entry.amountCents,
      );
    }
    final categories = _categories
        .where((category) => !category.archived)
        .toList();
    return ListView(
      children: [
        _pageHeader(
          'Orçamento',
          'Defina limites mensais e acompanhe o que resta.',
        ),
        _monthSelector(),
        const SizedBox(height: 8),
        ...categories.map((category) {
          final limit = _budgets[category.id] ?? 0;
          final used = expenseByCategory[category.id] ?? 0;
          final ratio = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
          final over = limit > 0 && used > limit;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _categoryIcon(category, size: 38),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              limit == 0
                                  ? 'Sem limite definido'
                                  : 'Limite ${_currency.format(limit / 100)}',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _editBudget(category),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Editar limite',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: ratio,
                    minHeight: 7,
                    color: over ? Colors.red : Color(category.colorValue),
                    backgroundColor: const Color(0xFFF0F1EF),
                  ),
                  const SizedBox(height: 7),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      limit == 0
                          ? 'Usado ${_currency.format(used / 100)}'
                          : '${_currency.format(used / 100)} usado · ${over ? 'acima do limite' : '${_currency.format((limit - used) / 100)} restante'}',
                      style: TextStyle(
                        color: over
                            ? Colors.red.shade700
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 80),
      ],
    );
  }

  Future<void> _editBudget(ExpenseCategory category) async {
    final result = await showDialog<int?>(
      context: context,
      builder: (_) => MoneyLimitDialog(
        category: category,
        initialCents: _budgets[category.id],
        currency: _currency,
      ),
    );
    if (result == null) return;
    final next = {..._budgets};
    if (result <= 0) {
      next.remove(category.id);
    } else {
      next[category.id] = result;
    }
    await _persistBudgets(next);
  }

  Widget _toolsPage() => ListView(
    children: [
      _pageHeader(
        'Mais ferramentas',
        'Categorias, recorrências e cópias dos seus dados.',
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.category_outlined),
          title: const Text('Gerenciar categorias'),
          subtitle: const Text('Criar, renomear ou arquivar categorias.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _manageCategories,
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.sell_outlined),
          title: const Text('Gerenciar tags'),
          subtitle: Text(
            '${_tags.length} tags cadastradas para sugerir nos lançamentos.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _manageTags,
        ),
      ),
      const SizedBox(height: 18),
      _sectionHeading('Recorrências', action: null),
      const SizedBox(height: 8),
      if (_recurringRules.isEmpty)
        _emptyState(
          'Nenhuma recorrência',
          'Despesas parceladas cadastradas junto com um lançamento aparecem aqui.',
        ),
      ..._recurringRules.map(
        (rule) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: _categoryIcon(categoryFor(rule.categoryId, _categories)),
            title: Text(
              rule.description,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${rule.completedInstallments >= rule.totalInstallments
                  ? 'Concluída'
                  : rule.active
                  ? 'Próxima'
                  : 'Pausada'} · ${_dateFormat.format(rule.nextDue)} · ${rule.completedInstallments}/${rule.totalInstallments} parcelas',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  await _editRecurring(rule);
                }
                if (value == 'toggle') {
                  await _persistRecurring(
                    _recurringRules
                        .map(
                          (item) => item.id == rule.id
                              ? item.copyWith(active: !item.active)
                              : item,
                        )
                        .toList(),
                  );
                }
                if (value == 'delete') {
                  await _persistRecurring(
                    _recurringRules
                        .where((item) => item.id != rule.id)
                        .toList(),
                  );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                if (rule.completedInstallments < rule.totalInstallments)
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(rule.active ? 'Pausar' : 'Retomar'),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Excluir recorrência'),
                ),
              ],
            ),
            onTap: () => _editRecurring(rule),
          ),
        ),
      ),
      const SizedBox(height: 18),
      _sectionHeading('Dados e CSV', action: null),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Exportar CSV'),
              subtitle: const Text(
                'Editável em planilhas; inclui movimentos, tags, categorias, limites e recorrências.',
              ),
              onTap: _exportCsv,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Importar CSV'),
              subtitle: const Text(
                'Mescla ou substitui dados locais a partir de um CSV.',
              ),
              onTap: _importCsv,
            ),
          ],
        ),
      ),
      const SizedBox(height: 80),
    ],
  );

  Future<void> _editRecurring(RecurringRule rule) async {
    final updated = await showDialog<RecurringRule>(
      context: context,
      builder: (_) =>
          RecurringRuleEditDialog(
            rule: rule,
            categories: _categories,
            knownTags: _tags,
          ),
    );
    if (updated == null) return;
    await _persistRecurring(
      _recurringRules
          .map((item) => item.id == rule.id ? updated : item)
          .toList(),
    );
  }

  Future<void> _manageCategories() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Categorias'),
          content: SizedBox(
            width: 460,
            height: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _categories
                        .map(
                          (category) => ListTile(
                            leading: _categoryIcon(category, size: 34),
                            title: Text(category.label),
                            subtitle: category.archived
                                ? const Text(
                                    'Arquivada · lançamentos antigos preservados',
                                  )
                                : category.isCustom
                                ? const Text('Personalizada')
                                : null,
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  final edited =
                                      await showDialog<ExpenseCategory>(
                                        context: context,
                                        builder: (_) =>
                                            CategoryDialog(category: category),
                                      );
                                  if (edited != null) {
                                    final next = _categories
                                        .map(
                                          (item) => item.id == category.id
                                              ? edited
                                              : item,
                                        )
                                        .toList();
                                    await _persistCategories(next);
                                    refresh(() {});
                                  }
                                }
                                if (value == 'archive') {
                                  if (!category.archived &&
                                      _categories
                                              .where((item) => !item.archived)
                                              .length <=
                                          1) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Mantenha ao menos uma categoria ativa.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  final next = _categories
                                      .map(
                                        (item) => item.id == category.id
                                            ? ExpenseCategory(
                                                item.id,
                                                item.label,
                                                item.icon,
                                                item.colorValue,
                                                archived: !item.archived,
                                                isCustom: true,
                                              )
                                            : item,
                                      )
                                      .toList();
                                  await _persistCategories(next);
                                  refresh(() {});
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Renomear'),
                                ),
                                PopupMenuItem(
                                  value: 'archive',
                                  child: Text(
                                    category.archived ? 'Reativar' : 'Arquivar',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final created = await showDialog<ExpenseCategory>(
                      context: context,
                      builder: (_) => const CategoryDialog(),
                    );
                    if (created != null) {
                      await _persistCategories([..._categories, created]);
                      refresh(() {});
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Nova categoria'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Concluir'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manageTags() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Tags'),
          content: SizedBox(
            width: 420,
            height: 420,
            child: Column(
              children: [
                Expanded(
                  child: _tags.isEmpty
                      ? const Center(child: Text('Ainda não há tags.'))
                      : ListView(
                          children: _tags
                              .map(
                                (tag) => ListTile(
                                  leading: const Icon(Icons.sell_outlined),
                                  title: Text(tag),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (action) async {
                                      if (action == 'edit') {
                                        final edited = await showDialog<String>(
                                          context: context,
                                          builder: (_) =>
                                              TagInputDialog(initialTag: tag),
                                        );
                                        if (edited == null || edited == tag)
                                          return;
                                        await _persistTags(
                                          _tags
                                              .where((item) => item != tag)
                                              .followedBy([edited])
                                              .toList(),
                                        );
                                        await _persist(
                                          _expenses
                                              .map(
                                                (entry) => entry.copyWith(
                                                  tags: entry.tags
                                                      .map(
                                                        (item) => item == tag
                                                            ? edited
                                                            : item,
                                                      )
                                                      .toSet()
                                                      .toList(),
                                                ),
                                              )
                                              .toList(),
                                        );
                                        refresh(() {});
                                      } else if (action == 'remove') {
                                        await _persist(
                                          _expenses
                                              .map(
                                                (entry) => entry.copyWith(
                                                  tags: entry.tags
                                                      .where(
                                                        (item) => item != tag,
                                                      )
                                                      .toList(),
                                                ),
                                              )
                                              .toList(),
                                        );
                                        await _persistTags(
                                          _tags
                                              .where((item) => item != tag)
                                              .toList(),
                                        );
                                        refresh(() {});
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text(
                                          'Renomear em todos os lançamentos',
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remover dos lançamentos'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final created = await showDialog<String>(
                      context: context,
                      builder: (_) => const TagInputDialog(),
                    );
                    if (created == null) return;
                    await _persistTags([..._tags, created]);
                    refresh(() {});
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Nova tag'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Concluir'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    try {
      final contents = await _repository.exportCsv();
      await FileSaver.instance.saveAs(
        name: 'gastoclaro_despesas',
        bytes: Uint8List.fromList(utf8.encode(contents)),
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('CSV exportado.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível exportar o backup.')),
        );
      }
    }
  }

  Future<void> _importCsv() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Arquivo CSV', extensions: ['csv']),
        ],
      );
      if (file == null) return;
      final contents = utf8.decode(await file.readAsBytes());
      final backup = _repository.decodeCsv(contents);
      if (!mounted) return;
      final mode = await showDialog<bool?>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importar arquivo'),
          content: Text(
            '${backup.entries.length} movimentos, ${backup.categories.length} categorias personalizadas e ${backup.recurringRules.length} recorrências. Escolha como importar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Mesclar'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Substituir dados'),
            ),
          ],
        ),
      );
      if (mode == null) return;
      await _repository.restoreBackup(backup, merge: mode);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Arquivo importado.')));
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível importar este arquivo.'),
          ),
        );
      }
    }
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

  Widget _expenseTile(
    Expense expense, {
    bool actions = false,
    bool selectionMode = false,
    bool selected = false,
    VoidCallback? onSelect,
  }) {
    final category = categoryFor(expense.categoryId, _categories);
    return GestureDetector(
      onDoubleTap: selectionMode ? null : () => _openExpense(expense: expense),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: selectionMode
            ? Checkbox(value: selected, onChanged: (_) => onSelect?.call())
            : _categoryIcon(category),
        onTap: selectionMode ? onSelect : null,
        title: Text(
          expense.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Wrap(
          spacing: 5,
          runSpacing: -6,
          children: [
            Text('${category.label} · ${_dateFormat.format(expense.spentAt)}'),
            ...expense.tags.map(_tagBadge),
            if (expense.notes?.trim().isNotEmpty == true)
              Text(
                expense.notes!.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '− ${_currency.format(expense.amountCents / 100)}',
              style: TextStyle(fontWeight: FontWeight.w700),
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
      ),
    );
  }

  Widget _tagBadge(String tag) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .16),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.sell_outlined,
          size: 12,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 4),
        Text(
          tag,
          style: TextStyle(
            fontSize: 11,
            height: 1.15,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    ),
  );

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
    _ => _categoryIconData(name),
  };
}

int? _amountToCents(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  final cents = int.tryParse(digits);
  if (cents == null || cents <= 0 || cents > 99999999999) return null;
  return cents;
}

class CentavosInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final cents = int.tryParse(digits);
    if (cents == null || cents > 99999999999) return oldValue;
    final formatted = NumberFormat('#,##0.00', 'pt_BR').format(cents / 100);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

DateTime _advanceMonthly(DateTime date, {int? preferredDay}) {
  final nextMonth = date.month + 1;
  final lastDay = DateTime(date.year, nextMonth + 1, 0).day;
  return DateTime(
    date.year,
    nextMonth,
    (preferredDay ?? date.day).clamp(1, lastDay),
  );
}

Future<void> _applyDueRecurringExpenses(ExpenseRepository repository) async {
  final expenses = await repository.load();
  final rules = await repository.loadRecurringRules();
  final today = DateUtils.dateOnly(DateTime.now());
  var changed = false;
  for (var index = 0; index < rules.length; index++) {
    final rule = rules[index];
    if (!rule.active) continue;
    var nextDue = DateUtils.dateOnly(rule.nextDue);
    var completed = rule.completedInstallments;
    while (completed < rule.totalInstallments && !nextDue.isAfter(today)) {
      final expenseId = '${rule.id}_${DateFormat('yyyyMMdd').format(nextDue)}';
      if (!expenses.any((entry) => entry.id == expenseId)) {
        expenses.add(
          Expense(
            id: expenseId,
            amountCents: rule.amountCents,
            description: rule.description,
            categoryId: rule.categoryId,
            tags: rule.tags,
            categorySetAt: nextDue,
            spentAt: nextDue,
            recurrenceId: rule.id,
            source: ExpenseSource.autoRule,
            categorizationMethod: CategorizationMethod.automatic,
          ),
        );
      }
      completed++;
      nextDue = _advanceMonthly(nextDue, preferredDay: rule.dayOfMonth);
      changed = true;
    }
    if (completed != rule.completedInstallments) {
      rules[index] = rule.copyWith(
        completedInstallments: completed,
        nextDue: nextDue,
        active: completed < rule.totalInstallments,
      );
    }
  }
  if (!changed) return;
  expenses.sort((a, b) => b.spentAt.compareTo(a.spentAt));
  await repository.saveAll(expenses);
  await repository.saveRecurringRules(rules);
}

class MoneyLimitDialog extends StatefulWidget {
  const MoneyLimitDialog({
    super.key,
    required this.category,
    required this.initialCents,
    required this.currency,
  });
  final ExpenseCategory category;
  final int? initialCents;
  final NumberFormat currency;
  @override
  State<MoneyLimitDialog> createState() => _MoneyLimitDialogState();
}

class _MoneyLimitDialogState extends State<MoneyLimitDialog> {
  late final TextEditingController _amount;
  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.initialCents == null
          ? ''
          : (widget.initialCents! / 100)
                .toStringAsFixed(2)
                .replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Limite · ${widget.category.label}'),
    content: TextField(
      controller: _amount,
      keyboardType: TextInputType.number,
      inputFormatters: [CentavosInputFormatter()],
      decoration: const InputDecoration(
        labelText: 'Limite mensal',
        prefixText: 'R\$ ',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, 0),
        child: const Text('Remover limite'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final amount = _amountToCents(_amount.text);
          if (amount != null) Navigator.pop(context, amount);
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}

class CategoryDialog extends StatefulWidget {
  const CategoryDialog({super.key, this.category});
  final ExpenseCategory? category;
  @override
  State<CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<CategoryDialog> {
  late final TextEditingController _label;
  late String _icon;
  static const _colors = [
    0xFFE77B45,
    0xFF6486C5,
    0xFF55A69A,
    0xFFD66B7A,
    0xFF9271C8,
    0xFFE5AE48,
    0xFF6B8F9F,
    0xFF8D929B,
  ];
  late int _color;
  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.category?.label ?? '');
    _icon = widget.category?.icon ?? 'more_horiz';
    _color = widget.category?.colorValue ?? _colors.first;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.category == null ? 'Nova categoria' : 'Editar categoria',
    ),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _label,
            maxLength: 24,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _icon,
            decoration: const InputDecoration(labelText: 'Ícone'),
            selectedItemBuilder: (context) => _categoryIconOptions
                .map(
                  (option) => Row(
                    children: [
                      Icon(option.$3, size: 20),
                      const SizedBox(width: 10),
                      Text(option.$2),
                    ],
                  ),
                )
                .toList(),
            items: _categoryIconOptions
                .map(
                  (option) => DropdownMenuItem(
                    value: option.$1,
                    child: Row(
                      children: [
                        Icon(option.$3, size: 20),
                        const SizedBox(width: 10),
                        Text(option.$2),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _icon = value ?? _icon),
          ),
          const SizedBox(height: 12),
          const Text('Cor'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _colors
                .map(
                  (color) => InkWell(
                    onTap: () => setState(() => _color = color),
                    child: CircleAvatar(
                      radius: _color == color ? 17 : 14,
                      backgroundColor: Color(color),
                      child: _color == color
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 17,
                            )
                          : null,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final name = _label.text.trim();
          if (name.isEmpty) return;
          Navigator.pop(
            context,
            ExpenseCategory(
              widget.category?.id ??
                  'custom_${DateTime.now().microsecondsSinceEpoch}',
              name,
              _icon,
              _color,
              archived: widget.category?.archived ?? false,
              isCustom: true,
            ),
          );
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}

class TagPairDialog extends StatefulWidget {
  const TagPairDialog({super.key, this.initialKey, this.initialValue});
  final String? initialKey;
  final String? initialValue;

  @override
  State<TagPairDialog> createState() => _TagPairDialogState();
}

class _TagPairDialogState extends State<TagPairDialog> {
  late final TextEditingController _name;
  late final TextEditingController _value;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialKey ?? '');
    _value = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initialKey == null ? 'Adicionar tag' : 'Editar tag'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nome',
              hintText: 'Responsável, lugar, viagem…',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _value,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Valor',
              hintText: 'Ana, Mercado, Santiago…',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          final value = _value.text.trim();
          if (name.isNotEmpty && value.isNotEmpty)
            Navigator.pop(context, MapEntry(name, value));
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}

class TagInputDialog extends StatefulWidget {
  const TagInputDialog({super.key, this.initialTag});
  final String? initialTag;
  @override
  State<TagInputDialog> createState() => _TagInputDialogState();
}

class _TagInputDialogState extends State<TagInputDialog> {
  late final TextEditingController _tag;
  @override
  void initState() {
    super.initState();
    _tag = TextEditingController(text: widget.initialTag ?? '');
  }

  @override
  void dispose() {
    _tag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initialTag == null ? 'Adicionar tag' : 'Renomear tag'),
    content: SizedBox(
      width: 380,
      child: TextField(
        controller: _tag,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Tag'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final tag = _tag.text.trim();
          if (tag.isNotEmpty) Navigator.pop(context, tag);
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}

class RecurringRuleEditDialog extends StatefulWidget {
  const RecurringRuleEditDialog({
    super.key,
    required this.rule,
    required this.categories,
    required this.knownTags,
  });

  final RecurringRule rule;
  final List<ExpenseCategory> categories;
  final List<String> knownTags;

  @override
  State<RecurringRuleEditDialog> createState() =>
      _RecurringRuleEditDialogState();
}

class _RecurringRuleEditDialogState extends State<RecurringRuleEditDialog> {
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _installments;
  late String _category;
  late DateTime _nextDue;
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _description = TextEditingController(text: rule.description);
    _amount = TextEditingController(
      text: (rule.amountCents / 100).toStringAsFixed(2).replaceAll('.', ','),
    );
    _installments = TextEditingController(text: '${rule.totalInstallments}');
    _category = rule.categoryId;
    _nextDue = rule.nextDue;
    _tags = [...rule.tags];
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _installments.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firstAllowed = widget.rule.completedInstallments < 2
        ? 2
        : widget.rule.completedInstallments;
    final lastAllowed = widget.rule.totalInstallments > 60
        ? widget.rule.totalInstallments
        : 60;
    return AlertDialog(
      title: const Text('Editar recorrência'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [CentavosInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Valor das próximas parcelas',
                  prefixText: 'R\$ ',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: widget.categories
                    .where(
                      (category) =>
                          !category.archived || category.id == _category,
                    )
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Row(
                          children: [
                            Icon(
                              _categoryIconData(category.icon),
                              color: Color(category.colorValue),
                              size: 19,
                            ),
                            const SizedBox(width: 9),
                            Text(category.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _category = value ?? _category),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _installments,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Total de parcelas',
                  helperText: 'Mínimo $firstAllowed',
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Tags', style: Theme.of(context).textTheme.titleSmall),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: widget.knownTags.map((tag) => FilterChip(
                  label: Text(tag),
                  selected: _tags.contains(tag),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _tags.add(tag);
                    } else {
                      _tags.remove(tag);
                    }
                  }),
                )).toList(),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Próximo vencimento'),
                subtitle: Text(
                  DateFormat('dd/MM/yyyy', 'pt_BR').format(_nextDue),
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: _nextDue,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (selected != null) setState(() => _nextDue = selected);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final cents = _amountToCents(_amount.text);
            final installments = int.tryParse(_installments.text);
            if (_description.text.trim().isEmpty ||
                cents == null ||
                installments == null ||
                installments < firstAllowed ||
                installments > lastAllowed) return;
            Navigator.pop(
              context,
              widget.rule.copyWith(
                description: _description.text.trim(),
                amountCents: cents,
                categoryId: _category,
                totalInstallments: installments,
                dayOfMonth: _nextDue.day,
                nextDue: _nextDue,
                active: installments > widget.rule.completedInstallments,
                tags: _tags,
              ),
            );
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class ExpenseDialog extends StatefulWidget {
  const ExpenseDialog({
    super.key,
    this.expense,
    this.quickEntry = false,
    required this.currency,
    required this.categories,
    required this.knownTags,
    required this.history,
  });
  final Expense? expense;
  final bool quickEntry;
  final NumberFormat currency;
  final List<ExpenseCategory> categories;
  final List<String> knownTags;
  final List<Expense> history;

  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class ExpenseFormResult {
  const ExpenseFormResult(this.expense, {this.recurringRule});

  final Expense expense;
  final RecurringRule? recurringRule;
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late final FocusNode _amountFocus;
  late DateTime _date;
  late String _category;
  bool _manualCategory = false;
  bool _didChooseCategory = false;
  late List<String> _tags;
  late List<String> _knownTags;
  bool _notesExpanded = false;
  bool _repeatMonthly = false;
  int _totalInstallments = 2;

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
    _notes = TextEditingController(text: expense?.notes ?? '');
    _notesExpanded = expense?.notes?.trim().isNotEmpty ?? false;
    _amountFocus = FocusNode()..addListener(_formatAmountOnBlur);
    _date = expense?.spentAt ?? DateTime.now();
    _category = expense?.categoryId ?? 'other';
    _tags = [...?expense?.tags];
    _knownTags = {...widget.knownTags, ..._tags}.toList();
    _manualCategory =
        expense?.categorizationMethod == CategorizationMethod.manual;
    _didChooseCategory = false;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _notes.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  void _formatAmountOnBlur() {
    if (_amountFocus.hasFocus) return;
    final cents = _parseCents(_amount.text);
    if (cents == null) return;
    final formatted = NumberFormat('#,##0.00', 'pt_BR').format(cents / 100);
    if (_amount.text != formatted) {
      _amount.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  void _descriptionChanged(String value) {
    if (_manualCategory || _didChooseCategory) return;
    final suggested = suggestCategoryFromHistory(
      value,
      widget.history,
      widget.categories,
    );
    setState(() => _category = suggested ?? 'other');
  }

  Future<void> _addTag() async {
    final tag = await showDialog<String>(
      context: context,
      builder: (_) => const TagInputDialog(),
    );
    if (tag != null) {
      setState(() {
        _tags = {..._tags, tag}.toList();
        _knownTags = {..._knownTags, tag}.toList();
      });
    }
  }

  int? _parseCents(String value) {
    return _amountToCents(value);
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
                focusNode: _amountFocus,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                inputFormatters: [CentavosInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Valor da despesa',
                  prefixText: 'R\$  ',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) => _parseCents(value ?? '') == null
                    ? 'Informe um valor maior que zero'
                    : null,
              ),
              if (_amountFocus.hasFocus && _parseCents(_amount.text) != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: Text(
                      'Valor: ${widget.currency.format(_parseCents(_amount.text)! / 100)}',
                    ),
                  ),
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
                items: widget.categories
                    .where(
                      (category) =>
                          !category.archived || category.id == _category,
                    )
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Row(
                          children: [
                            Icon(
                              _categoryIconData(category.icon),
                              color: Color(category.colorValue),
                              size: 19,
                            ),
                            const SizedBox(width: 9),
                            Text(category.label),
                          ],
                        ),
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
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tags',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ..._knownTags.map(
                    (tag) => FilterChip(
                      label: Text(tag),
                      selected: _tags.contains(tag),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _tags.add(tag);
                        } else {
                          _tags.remove(tag);
                        }
                      }),
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Nova tag'),
                    onPressed: _addTag,
                  ),
                ],
              ),
              if (widget.expense == null) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Repetir mensalmente'),
                  value: _repeatMonthly,
                  onChanged: (value) =>
                      setState(() => _repeatMonthly = value ?? false),
                ),
                if (_repeatMonthly)
                  TextFormField(
                    initialValue: '$_totalInstallments',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Total de parcelas (inclui esta)',
                      prefixIcon: Icon(Icons.repeat),
                      helperText: 'Mínimo 2, máximo 60',
                    ),
                    onChanged: (value) {
                      final count = int.tryParse(value);
                      if (count != null) _totalInstallments = count;
                    },
                    validator: (value) {
                      final count = int.tryParse(value ?? '');
                      return count == null || count < 2 || count > 60
                          ? 'Informe um total entre 2 e 60'
                          : null;
                    },
                  ),
              ],
              const SizedBox(height: 4),
              if (!_notesExpanded)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _notesExpanded = true),
                    icon: const Icon(Icons.notes_outlined, size: 18),
                    label: const Text('Adicionar notas'),
                  ),
                )
              else
                TextFormField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                    alignLabelWithHint: true,
                  ),
                ),
              const SizedBox(height: 12),
              if (!widget.quickEntry)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text('Data da despesa'),
                  subtitle: Text(
                    DateFormat('dd/MM/yyyy', 'pt_BR').format(_date),
                  ),
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
        child: Text(widget.quickEntry ? 'Fechar' : 'Cancelar'),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(widget.quickEntry ? 'Confirmar' : 'Salvar despesa'),
      ),
    ],
  );

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final previous = widget.expense;
    final id = previous?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final now = DateTime.now();
    final spentAt = widget.quickEntry ? now : _date;
    final recurrenceId = _repeatMonthly
        ? 'rec_${DateTime.now().microsecondsSinceEpoch}'
        : previous?.recurrenceId;
    final recurringRule = _repeatMonthly
        ? RecurringRule(
            id: recurrenceId!,
            description: _description.text.trim(),
            amountCents: _parseCents(_amount.text)!,
            categoryId: _category,
            totalInstallments: _totalInstallments,
            dayOfMonth: spentAt.day,
            completedInstallments: 1,
            nextDue: _advanceMonthly(spentAt),
            tags: _tags,
          )
        : null;
    Navigator.pop(
      context,
      ExpenseFormResult(
        Expense(
          id: id,
          amountCents: _parseCents(_amount.text)!,
          description: _description.text.trim(),
          categoryId: _category,
          spentAt: spentAt,
          categorySetAt: now,
          recurrenceId: recurrenceId,
          tags: _tags,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          source: previous?.source ?? ExpenseSource.manual,
          categorizationMethod: _manualCategory || _didChooseCategory
              ? CategorizationMethod.manual
              : CategorizationMethod.automatic,
        ),
        recurringRule: recurringRule,
      ),
    );
  }
}
