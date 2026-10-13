import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/expense.dart';

class BackupData {
  const BackupData({
    required this.entries,
    required this.categories,
    required this.budgets,
    required this.recurringRules,
  });

  final List<Expense> entries;
  final List<ExpenseCategory> categories;
  final Map<String, int> budgets;
  final List<RecurringRule> recurringRules;
}

class ExpenseRepository {
  static const _legacyEntriesKey = 'controle_gastos.expenses.v1';
  static const _entriesKey = 'controle_gastos.entries.v2';
  static const _categoriesKey = 'controle_gastos.categories.v1';
  static const _budgetsKey = 'controle_gastos.budgets.v1';
  static const _recurringKey = 'controle_gastos.recurring.v1';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<List<Expense>> load() async {
    final raw =
        await _preferences.getString(_entriesKey) ??
        await _preferences.getString(_legacyEntriesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final rows = jsonDecode(raw) as List<dynamic>;
      return rows
          .map((row) => Expense.fromJson(row as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.spentAt.compareTo(a.spentAt));
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  Future<void> saveAll(List<Expense> entries) => _preferences.setString(
    _entriesKey,
    jsonEncode(entries.map((entry) => entry.toJson()).toList()),
  );

  Future<List<ExpenseCategory>> loadCategories() async {
    final raw = await _preferences.getString(_categoriesKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((row) => ExpenseCategory.fromJson(row as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  Future<void> saveCategories(List<ExpenseCategory> categories) =>
      _preferences.setString(
        _categoriesKey,
        jsonEncode(categories.map((category) => category.toJson()).toList()),
      );

  Future<Map<String, int>> loadBudgets() async {
    final raw = await _preferences.getString(_budgetsKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as int),
      );
    } on FormatException {
      return {};
    } on TypeError {
      return {};
    }
  }

  Future<void> saveBudgets(Map<String, int> budgets) =>
      _preferences.setString(_budgetsKey, jsonEncode(budgets));

  Future<List<RecurringRule>> loadRecurringRules() async {
    final raw = await _preferences.getString(_recurringKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((row) => RecurringRule.fromJson(row as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  Future<void> saveRecurringRules(List<RecurringRule> rules) =>
      _preferences.setString(
        _recurringKey,
        jsonEncode(rules.map((rule) => rule.toJson()).toList()),
      );

  Future<String> exportBackup() async => jsonEncode({
    'format': 'controle_gastos_backup',
    'schemaVersion': 2,
    'exportedAt': DateTime.now().toIso8601String(),
    'entries': (await load()).map((entry) => entry.toJson()).toList(),
    'categories': (await loadCategories())
        .map((category) => category.toJson())
        .toList(),
    'budgets': await loadBudgets(),
    'recurringRules': (await loadRecurringRules())
        .map((rule) => rule.toJson())
        .toList(),
  });

  BackupData decodeBackup(String contents) {
    final json = jsonDecode(contents) as Map<String, dynamic>;
    if (json['format'] != 'controle_gastos_backup' ||
        json['schemaVersion'] != 2) {
      throw const FormatException('Este arquivo não é um backup compatível.');
    }
    final entries = (json['entries'] as List<dynamic>)
        .map((row) => Expense.fromJson(row as Map<String, dynamic>))
        .toList();
    final categories = (json['categories'] as List<dynamic>)
        .map((row) => ExpenseCategory.fromJson(row as Map<String, dynamic>))
        .toList();
    final budgets = (json['budgets'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as int),
    );
    final recurring = (json['recurringRules'] as List<dynamic>)
        .map((row) => RecurringRule.fromJson(row as Map<String, dynamic>))
        .toList();
    if (entries.map((entry) => entry.id).toSet().length != entries.length ||
        categories.map((category) => category.id).toSet().length !=
            categories.length ||
        recurring.map((rule) => rule.id).toSet().length != recurring.length) {
      throw const FormatException(
        'O backup contém identificadores duplicados.',
      );
    }
    final categoryIds = {
      ...expenseCategories.map((category) => category.id),
      ...categories.map((category) => category.id),
    };
    if (entries.any((entry) => entry.amountCents <= 0) ||
        budgets.values.any((amount) => amount <= 0) ||
        categories.any((category) => category.label.trim().isEmpty) ||
        entries.any((entry) => !categoryIds.contains(entry.categoryId)) ||
        recurring.any((rule) => !categoryIds.contains(rule.categoryId)) ||
        budgets.keys.any((categoryId) => !categoryIds.contains(categoryId))) {
      throw const FormatException('O backup contém valores inválidos.');
    }
    return BackupData(
      entries: entries,
      categories: categories,
      budgets: budgets,
      recurringRules: recurring,
    );
  }

  Future<void> restoreBackup(BackupData backup, {required bool merge}) async {
    if (!merge) {
      await saveAll(backup.entries);
      await saveCategories(backup.categories);
      await saveBudgets(backup.budgets);
      await saveRecurringRules(backup.recurringRules);
      return;
    }
    final currentEntries = await load();
    final knownEntryIds = currentEntries.map((entry) => entry.id).toSet();
    await saveAll([
      ...currentEntries,
      ...backup.entries.where((entry) => !knownEntryIds.contains(entry.id)),
    ]);
    final currentCategories = await loadCategories();
    final knownCategoryIds = currentCategories
        .map((category) => category.id)
        .toSet();
    await saveCategories([
      ...currentCategories,
      ...backup.categories.where(
        (category) => !knownCategoryIds.contains(category.id),
      ),
    ]);
    await saveBudgets({...backup.budgets, ...await loadBudgets()});
    final currentRules = await loadRecurringRules();
    final knownRuleIds = currentRules.map((rule) => rule.id).toSet();
    await saveRecurringRules([
      ...currentRules,
      ...backup.recurringRules.where((rule) => !knownRuleIds.contains(rule.id)),
    ]);
  }
}
