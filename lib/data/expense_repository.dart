import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/expense.dart';

class ExpenseRepository {
  static const _storageKey = 'controle_gastos.expenses.v1';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<List<Expense>> load() async {
    final raw = await _preferences.getString(_storageKey);
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

  Future<void> saveAll(List<Expense> expenses) async {
    await _preferences.setString(
      _storageKey,
      jsonEncode(expenses.map((expense) => expense.toJson()).toList()),
    );
  }
}
