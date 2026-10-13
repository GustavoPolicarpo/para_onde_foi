import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:file_selector/file_selector.dart';
import 'package:file_saver/file_saver.dart';

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
  List<ExpenseCategory> _categories = expenseCategories;
  Map<String, int> _budgets = {};
  List<RecurringRule> _recurringRules = [];
  List<String> _tags = [];
  final _searchController = TextEditingController();
  DateTimeRange? _dateRange;
  EntryType? _typeFilter;
  final Set<String> _movementTagFilters = {};
  final Set<String> _reportTagFilters = {};
  bool _reportGroupByTags = false;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _loading = true;
  int _page = 0;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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

  int get _monthExpensesTotal => _monthExpenses
      .where((entry) => entry.type == EntryType.expense)
      .fold(0, (sum, entry) => sum + entry.amountCents);
  int get _monthIncomeTotal => _monthExpenses
      .where((entry) => entry.type == EntryType.income)
      .fold(0, (sum, entry) => sum + entry.amountCents);
  int get _monthBalance => _monthIncomeTotal - _monthExpensesTotal;

  Future<void> _persist(List<Expense> next) async {
    next.sort((a, b) => b.spentAt.compareTo(a.spentAt));
    await _repository.saveAll(next);
    if (mounted) setState(() => _expenses = next);
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
  }

  Future<void> _persistRecurring(List<RecurringRule> next) async {
    await _repository.saveRecurringRules(next);
    if (mounted) setState(() => _recurringRules = next);
  }

  Future<void> _openExpense({Expense? expense}) async {
    final result = await showDialog<Expense>(
      context: context,
      builder: (_) => ExpenseDialog(
        expense: expense,
        currency: _currency,
        categories: _categories,
        knownTags: _tags,
      ),
    );
    if (result == null) return;
    final next = [..._expenses];
    final index = next.indexWhere((item) => item.id == result.id);
    if (index < 0) {
      next.add(result);
    } else {
      next[index] = result;
    }
    await _persistTags({..._tags, ...result.tags}.toList());
    await _persist(next);
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
      builder: (_) => TagInputDialog(suggestions: _tags),
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
                  'Saldo do mês',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                Text(
                  _currency.format(_monthBalance / 100),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    color: _monthBalance < 0
                        ? Colors.red.shade700
                        : Colors.green.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Receitas ${_currency.format(_monthIncomeTotal / 100)}  ·  Despesas ${_currency.format(_monthExpensesTotal / 100)}',
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
          'Movimentos recentes',
          action: 'Ver todos',
          onAction: () => setState(() => _page = 1),
        ),
        const SizedBox(height: 8),
        if (latest.isEmpty)
          _emptyState(
            'Nenhum movimento neste mês',
            'Registre uma entrada ou despesa para começar.',
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
                  (_typeFilter == null || expense.type == _typeFilter) &&
                  ('${expense.description} ${expense.tags.join(' ')}')
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
                'Entradas e despesas do período selecionado.',
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
            Expanded(
              child: DropdownButtonFormField<EntryType?>(
                initialValue: _typeFilter,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem<EntryType?>(
                    value: null,
                    child: Text('Todos'),
                  ),
                  DropdownMenuItem<EntryType?>(
                    value: EntryType.expense,
                    child: Text('Despesas'),
                  ),
                  DropdownMenuItem<EntryType?>(
                    value: EntryType.income,
                    child: Text('Receitas'),
                  ),
                ],
                onChanged: (value) => setState(() => _typeFilter = value),
              ),
            ),
            const SizedBox(width: 8),
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
      (entry) =>
          entry.type == EntryType.expense &&
          _reportTagFilters.every(entry.tags.contains),
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
    for (final entry in _monthExpenses.where(
      (entry) => entry.type == EntryType.expense,
    )) {
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
      _sectionHeading(
        'Recorrências',
        action: 'Adicionar',
        onAction: _addRecurring,
      ),
      const SizedBox(height: 8),
      if (_recurringRules.isEmpty)
        _emptyState(
          'Nenhuma recorrência',
          'Cadastre uma conta ou receita periódica e confirme cada lançamento quando vencer.',
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
              '${rule.active ? 'Próxima' : 'Pausada'} · ${_dateFormat.format(rule.nextDue)} · ${_frequencyLabel(rule.frequency)}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'confirm') {
                  await _confirmRecurring(rule);
                }
                if (value == 'toggle') {
                  await _persistRecurring(
                    _recurringRules
                        .map(
                          (item) => item.id == rule.id
                              ? RecurringRule(
                                  id: item.id,
                                  description: item.description,
                                  amountCents: item.amountCents,
                                  categoryId: item.categoryId,
                                  type: item.type,
                                  frequency: item.frequency,
                                  nextDue: item.nextDue,
                                  active: !item.active,
                                )
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
                if (rule.active)
                  const PopupMenuItem(
                    value: 'confirm',
                    child: Text('Confirmar lançamento'),
                  ),
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
            onTap: () => _showRecurringDetail(rule),
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

  String _frequencyLabel(RecurrenceFrequency frequency) => switch (frequency) {
    RecurrenceFrequency.weekly => 'Toda semana',
    RecurrenceFrequency.monthly => 'Todo mês',
    RecurrenceFrequency.yearly => 'Todo ano',
  };

  DateTime _advanceDate(DateTime date, RecurrenceFrequency frequency) =>
      switch (frequency) {
        RecurrenceFrequency.weekly => date.add(const Duration(days: 7)),
        RecurrenceFrequency.monthly => DateTime(
          date.year,
          date.month + 1,
          date.day.clamp(1, DateTime(date.year, date.month + 2, 0).day),
        ),
        RecurrenceFrequency.yearly => DateTime(
          date.year + 1,
          date.month,
          date.day.clamp(1, DateTime(date.year + 1, date.month + 1, 0).day),
        ),
      };

  Future<void> _confirmRecurring(RecurringRule rule) async {
    final exists = _expenses.any(
      (entry) =>
          entry.recurrenceId == rule.id &&
          entry.spentAt.year == rule.nextDue.year &&
          entry.spentAt.month == rule.nextDue.month &&
          entry.spentAt.day == rule.nextDue.day,
    );
    if (!exists) {
      await _persist([
        ..._expenses,
        Expense(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          amountCents: rule.amountCents,
          description: rule.description,
          categoryId: rule.categoryId,
          spentAt: rule.nextDue,
          type: rule.type,
          recurrenceId: rule.id,
        ),
      ]);
    }
    await _persistRecurring(
      _recurringRules
          .map(
            (item) => item.id == rule.id
                ? RecurringRule(
                    id: item.id,
                    description: item.description,
                    amountCents: item.amountCents,
                    categoryId: item.categoryId,
                    type: item.type,
                    frequency: item.frequency,
                    nextDue: _advanceDate(item.nextDue, item.frequency),
                    active: item.active,
                  )
                : item,
          )
          .toList(),
    );
  }

  Future<void> _addRecurring() async {
    final rule = await showDialog<RecurringRule>(
      context: context,
      builder: (_) =>
          RecurringDialog(categories: _categories, currency: _currency),
    );
    if (rule != null) await _persistRecurring([..._recurringRules, rule]);
  }

  Future<void> _showRecurringDetail(RecurringRule rule) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(rule.description),
        content: Text(
          '${rule.type == EntryType.expense ? 'Despesa' : 'Entrada'} de ${_currency.format(rule.amountCents / 100)} · ${_frequencyLabel(rule.frequency)}\nPróximo vencimento: ${_dateFormat.format(rule.nextDue)}\nO app não lança automaticamente; confirme para criar o movimento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
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
                                          builder: (_) => TagInputDialog(
                                            initialTag: tag,
                                            suggestions: _tags,
                                          ),
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
                      builder: (_) => TagInputDialog(suggestions: _tags),
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
        name: 'controle_gastos',
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
    return Card(
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
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${expense.type == EntryType.income ? '+' : '−'} ${_currency.format(expense.amountCents / 100)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: expense.type == EntryType.income
                    ? Colors.green.shade800
                    : null,
              ),
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

int? _amountToCents(String value) {
  var normalized = value.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (normalized.contains(',')) {
    normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
  } else if (normalized.contains('.')) {
    final decimals = normalized.length - normalized.lastIndexOf('.') - 1;
    if (decimals == 3) normalized = normalized.replaceAll('.', '');
  }
  final amount = double.tryParse(normalized);
  if (amount == null || amount <= 0 || amount > 999999999) return null;
  return (amount * 100).round();
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
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            items: const [
              DropdownMenuItem(value: 'restaurant', child: Text('Alimentação')),
              DropdownMenuItem(value: 'home', child: Text('Casa')),
              DropdownMenuItem(
                value: 'directions_car',
                child: Text('Transporte'),
              ),
              DropdownMenuItem(value: 'favorite', child: Text('Saúde')),
              DropdownMenuItem(value: 'movie', child: Text('Lazer')),
              DropdownMenuItem(value: 'shopping_bag', child: Text('Compras')),
              DropdownMenuItem(value: 'receipt_long', child: Text('Contas')),
              DropdownMenuItem(value: 'more_horiz', child: Text('Outros')),
            ],
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

class RecurringDialog extends StatefulWidget {
  const RecurringDialog({
    super.key,
    required this.categories,
    required this.currency,
  });
  final List<ExpenseCategory> categories;
  final NumberFormat currency;
  @override
  State<RecurringDialog> createState() => _RecurringDialogState();
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
  const TagInputDialog({super.key, required this.suggestions, this.initialTag});
  final List<String> suggestions;
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _tag,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Tag',
              hintText: 'Ex.: SRS, Ana, Mercado ou Viagem Chile',
            ),
          ),
          if (widget.suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Sugestões'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: widget.suggestions
                  .map(
                    (tag) => ActionChip(
                      label: Text(tag),
                      onPressed: () => setState(() => _tag.text = tag),
                    ),
                  )
                  .toList(),
            ),
          ],
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
          final tag = _tag.text.trim();
          if (tag.isNotEmpty) Navigator.pop(context, tag);
        },
        child: const Text('Salvar'),
      ),
    ],
  );
}

class _RecurringDialogState extends State<RecurringDialog> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  EntryType _type = EntryType.expense;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  DateTime _nextDue = DateTime.now();
  late String _category;
  @override
  void initState() {
    super.initState();
    _category = widget.categories
        .firstWhere((category) => !category.archived)
        .id;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nova recorrência'),
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor',
                prefixText: 'R\$ ',
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<EntryType>(
              segments: const [
                ButtonSegment(value: EntryType.expense, label: Text('Despesa')),
                ButtonSegment(value: EntryType.income, label: Text('Receita')),
              ],
              selected: {_type},
              onSelectionChanged: (values) =>
                  setState(() => _type = values.first),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: widget.categories
                  .where((category) => !category.archived)
                  .map(
                    (category) => DropdownMenuItem(
                      value: category.id,
                      child: Text(category.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<RecurrenceFrequency>(
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: 'Frequência'),
              items: const [
                DropdownMenuItem(
                  value: RecurrenceFrequency.weekly,
                  child: Text('Semanal'),
                ),
                DropdownMenuItem(
                  value: RecurrenceFrequency.monthly,
                  child: Text('Mensal'),
                ),
                DropdownMenuItem(
                  value: RecurrenceFrequency.yearly,
                  child: Text('Anual'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _frequency = value ?? _frequency),
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
          if (_description.text.trim().isEmpty || cents == null) return;
          Navigator.pop(
            context,
            RecurringRule(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              description: _description.text.trim(),
              amountCents: cents,
              categoryId: _category,
              type: _type,
              frequency: _frequency,
              nextDue: _nextDue,
            ),
          );
        },
        child: const Text('Criar'),
      ),
    ],
  );
}

class ExpenseDialog extends StatefulWidget {
  const ExpenseDialog({
    super.key,
    this.expense,
    required this.currency,
    required this.categories,
    required this.knownTags,
  });
  final Expense? expense;
  final NumberFormat currency;
  final List<ExpenseCategory> categories;
  final List<String> knownTags;

  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late final FocusNode _amountFocus;
  late DateTime _date;
  late String _category;
  bool _manualCategory = false;
  bool _didChooseCategory = false;
  late EntryType _type;
  late List<String> _tags;

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
    _amountFocus = FocusNode()..addListener(_formatAmountOnBlur);
    _date = expense?.spentAt ?? DateTime.now();
    _category = expense?.categoryId ?? 'other';
    _type = expense?.type ?? EntryType.expense;
    _tags = [...?expense?.tags];
    _manualCategory =
        expense?.categorizationMethod == CategorizationMethod.manual;
    _didChooseCategory = false;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
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
    final suggested = suggestCategory(value, widget.categories);
    if (suggested != null) setState(() => _category = suggested);
  }

  Future<void> _addTag() async {
    final tag = await showDialog<String>(
      context: context,
      builder: (_) => TagInputDialog(suggestions: widget.knownTags),
    );
    if (tag != null) setState(() => _tags = {..._tags, tag}.toList());
  }

  int? _parseCents(String value) {
    return _amountToCents(value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.expense == null
          ? (_type == EntryType.income ? 'Nova receita' : 'Nova despesa')
          : (_type == EntryType.income ? 'Editar receita' : 'Editar despesa'),
    ),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _type == EntryType.income
                      ? 'Valor recebido'
                      : 'Valor da despesa',
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
              SegmentedButton<EntryType>(
                segments: const [
                  ButtonSegment(
                    value: EntryType.expense,
                    label: Text('Despesa'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                  ButtonSegment(
                    value: EntryType.income,
                    label: Text('Receita'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (values) =>
                    setState(() => _type = values.first),
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
                  ..._tags.map(
                    (tag) => InputChip(
                      label: Text(tag),
                      onDeleted: () => setState(() => _tags.remove(tag)),
                    ),
                  ),
                  ...widget.knownTags
                      .where((tag) => !_tags.contains(tag))
                      .map(
                        (tag) => ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(tag),
                          onPressed: () => setState(() => _tags.add(tag)),
                        ),
                      ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Nova tag'),
                    onPressed: _addTag,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(
                  _type == EntryType.income
                      ? 'Data do recebimento'
                      : 'Data da despesa',
                ),
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
      FilledButton(
        onPressed: _save,
        child: Text(
          _type == EntryType.income ? 'Salvar receita' : 'Salvar despesa',
        ),
      ),
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
        type: _type,
        tags: _tags,
        source: previous?.source ?? ExpenseSource.manual,
        categorizationMethod: _manualCategory || _didChooseCategory
            ? CategorizationMethod.manual
            : CategorizationMethod.automatic,
      ),
    );
  }
}
