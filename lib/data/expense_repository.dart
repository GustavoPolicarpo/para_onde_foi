import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/expense.dart';

class BackupData {
  const BackupData({
    required this.entries,
    required this.categories,
    required this.budgets,
    required this.recurringRules,
    this.tags = const [],
  });

  final List<Expense> entries;
  final List<ExpenseCategory> categories;
  final Map<String, int> budgets;
  final List<RecurringRule> recurringRules;
  final List<String> tags;
}

class ExpenseRepository {
  static final Csv _csv = Csv.excel();
  static const _csvHeaders = [
    'tipo_registro',
    'id',
    'valor',
    'descricao',
    'categoria',
    'data',
    'categoria_definida_em',
    'origem',
    'metodo_categorizacao',
    'recorrencia_id',
    'notas',
    'tag_nome',
    'tag_ids',
    'categoria_id',
    'categoria_icone',
    'categoria_cor',
    'categoria_arquivada',
    'limite_mensal',
    'parcelas_total',
    'parcelas_concluidas',
    'dia_vencimento',
    'proximo_vencimento',
    'ativa',
  ];
  static const _entriesKey = 'gasto_claro.entries.v1';
  static const _categoriesKey = 'gasto_claro.categories.v1';
  static const _budgetsKey = 'gasto_claro.budgets.v1';
  static const _recurringKey = 'gasto_claro.recurring.v1';
  static const _tagsKey = 'gasto_claro.tags.v1';
  static Map<String, String> _tagIds(Iterable<String> values) {
    String slug(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp('[áàâãä]'), 'a')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[íìîï]'), 'i')
        .replaceAll(RegExp('[óòôõö]'), 'o')
        .replaceAll(RegExp('[úùûü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final names = values.toSet().toList()..sort();
    final counts = <String, int>{};
    final ids = <String, String>{};
    for (final name in names) {
      final base = slug(name).isEmpty ? 'tag' : slug(name);
      final index = (counts[base] ?? 0) + 1;
      counts[base] = index;
      ids[name] = 'tag_$base${index == 1 ? '' : '_$index'}';
    }
    return ids;
  }

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<List<Expense>> load() async {
    final raw = await _preferences.getString(_entriesKey);
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

  Future<List<String>> loadTags() async {
    final raw = await _preferences.getString(_tagsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((value) => value.toString())
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  Future<void> saveTags(List<String> tags) =>
      _preferences.setString(_tagsKey, jsonEncode(tags.toSet().toList()));

  Future<String> exportCsv() async {
    final rows = <List<dynamic>>[_csvHeaders];
    final customCategories = await loadCategories();
    final categories = [...expenseCategories, ...customCategories];
    final entries = await load();
    final tags = await loadTags();
    final tagIds = _tagIds(tags);
    void addRow(String kind, Map<String, Object?> values) {
      rows.add(
        _csvHeaders
            .map(
              (header) =>
                  header == 'tipo_registro' ? kind : values[header] ?? '',
            )
            .toList(),
      );
    }

    for (final entry in entries) {
      final linkedTagIds = entry.tags.map((tag) => tagIds[tag]!).join(',');
      addRow('lancamento', {
        'id': entry.id,
        'valor': (entry.amountCents / 100)
            .toStringAsFixed(2)
            .replaceAll('.', ','),
        'descricao': entry.description,
        'categoria_id': entry.categoryId,
        'categoria': categoryFor(entry.categoryId, categories).label,
        'data': entry.spentAt.toIso8601String(),
        'categoria_definida_em': (entry.categorySetAt ?? entry.spentAt)
            .toIso8601String(),
        'origem': entry.source.name,
        'metodo_categorizacao': entry.categorizationMethod.name,
        'recorrencia_id': entry.recurrenceId ?? '',
        'notas': entry.notes ?? '',
        'tag_ids': linkedTagIds,
      });
    }
    for (final category in customCategories) {
      addRow('categoria', {
        'id': category.id,
        'categoria': category.label,
        'categoria_id': category.id,
        'categoria_icone': category.icon,
        'categoria_cor': category.colorValue,
        'categoria_arquivada': category.archived,
      });
    }
    for (final entry in (await loadBudgets()).entries) {
      addRow('orcamento', {
        'categoria_id': entry.key,
        'categoria': categoryFor(entry.key, categories).label,
        'limite_mensal': (entry.value / 100)
            .toStringAsFixed(2)
            .replaceAll('.', ','),
      });
    }
    for (final tag in tags) {
      addRow('tag_catalogo', {'id': tagIds[tag], 'tag_nome': tag});
    }
    for (final rule in await loadRecurringRules()) {
      final linkedTagIds = rule.tags.map((tag) => tagIds[tag]!).join(',');
      addRow('recorrencia', {
        'id': rule.id,
        'descricao': rule.description,
        'valor': (rule.amountCents / 100)
            .toStringAsFixed(2)
            .replaceAll('.', ','),
        'categoria_id': rule.categoryId,
        'categoria': categoryFor(rule.categoryId, categories).label,
        'parcelas_total': rule.totalInstallments,
        'parcelas_concluidas': rule.completedInstallments,
        'dia_vencimento': rule.dayOfMonth,
        'tag_ids': linkedTagIds,
        'proximo_vencimento': rule.nextDue.toIso8601String(),
        'ativa': rule.active,
      });
    }
    return _csv.encode(rows);
  }

  BackupData decodeCsv(String contents) {
    final source = contents.startsWith('\uFEFF')
        ? contents.substring(1)
        : contents;
    final rows = _csv.decode(source);
    if (rows.length < 2) throw const FormatException('O CSV não tem dados.');
    final headers = rows.first.map((value) => value.toString().trim()).toList();
    if (!_csvHeaders.every(headers.contains)) {
      throw const FormatException('O CSV não contém as colunas esperadas.');
    }
    final records = <Map<String, String>>[];
    for (final row in rows.skip(1)) {
      final values = <String, String>{};
      for (
        var index = 0;
        index < headers.length && index < row.length;
        index++
      ) {
        values[headers[index]] = row[index].toString();
      }
      records.add(values);
    }
    String value(Map<String, String> row, String key) => row[key] ?? '';
    int integer(Map<String, String> row, String key, {int fallback = 0}) =>
        int.tryParse(value(row, key)) ?? fallback;
    int money(Map<String, String> row, String key) {
      var raw = value(
        row,
        key,
      ).trim().replaceAll('R\$', '').replaceAll(' ', '');
      if (raw.contains(',')) raw = raw.replaceAll('.', '').replaceAll(',', '.');
      final amount = double.tryParse(raw);
      if (amount == null || amount < 0)
        throw const FormatException('Valor monetário inválido no CSV.');
      return (amount * 100).round();
    }

    bool boolean(
      Map<String, String> row,
      String key, {
      bool fallback = false,
    }) => switch (value(row, key).toLowerCase()) {
      'true' || '1' || 'sim' => true,
      'false' || '0' || 'nao' || 'não' => false,
      _ => fallback,
    };

    final entries = <String, Expense>{};
    final tagsByEntry = <String, Set<String>>{};
    final tagNamesById = <String, String>{};
    final tagCatalog = <String>{};
    for (final row in records.where(
      (row) =>
          value(row, 'tipo_registro').trim().toLowerCase() == 'tag_catalogo',
    )) {
      final label = value(row, 'tag_nome').trim();
      final id = value(row, 'id').trim();
      if (label.isEmpty || id.isEmpty) {
        throw const FormatException('Cada tag precisa de um ID e um nome.');
      }
      if (tagNamesById.containsKey(id)) {
        throw const FormatException('Há IDs de tag repetidos no CSV.');
      }
      tagNamesById[id] = label;
      tagCatalog.add(label);
    }
    final categories = <ExpenseCategory>[];
    for (final row in records.where(
      (row) => value(row, 'tipo_registro').trim().toLowerCase() == 'categoria',
    )) {
      final id = value(row, 'id');
      final label = value(row, 'categoria').trim();
      if (id.isEmpty || label.isEmpty)
        throw const FormatException('Categoria inválida no CSV.');
      categories.add(
        ExpenseCategory(
          id,
          label,
          value(row, 'categoria_icone').isEmpty
              ? 'more_horiz'
              : value(row, 'categoria_icone'),
          integer(row, 'categoria_cor', fallback: 0xFF8D929B),
          archived: boolean(row, 'categoria_arquivada'),
          isCustom: true,
        ),
      );
    }
    final allCategories = [...expenseCategories, ...categories];
    String categoryId(Map<String, String> row) {
      final label = value(row, 'categoria').trim().toLowerCase();
      final byLabel = allCategories.where(
        (item) => item.label.trim().toLowerCase() == label,
      );
      return byLabel.isNotEmpty ? byLabel.first.id : value(row, 'categoria_id');
    }

    final budgets = <String, int>{};
    final recurring = <RecurringRule>[];
    try {
      for (final row in records) {
        switch (value(row, 'tipo_registro').trim().toLowerCase()) {
          case 'lancamento':
            final entry = Expense(
              id: value(row, 'id'),
              amountCents: money(row, 'valor'),
              description: value(row, 'descricao'),
              categoryId: categoryId(row),
              spentAt: DateTime.parse(value(row, 'data')),
              categorySetAt: DateTime.parse(
                value(row, 'categoria_definida_em'),
              ),
              source: ExpenseSource.values.firstWhere(
                (item) => item.name == value(row, 'origem'),
                orElse: () => ExpenseSource.manual,
              ),
              categorizationMethod: CategorizationMethod.values.firstWhere(
                (item) => item.name == value(row, 'metodo_categorizacao'),
                orElse: () => CategorizationMethod.manual,
              ),
              recurrenceId: value(row, 'recorrencia_id').isEmpty
                  ? null
                  : value(row, 'recorrencia_id'),
              notes: value(row, 'notas').trim().isEmpty
                  ? null
                  : value(row, 'notas'),
            );
            final linkedTags = value(row, 'tag_ids')
                .split(',')
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .map((id) => tagNamesById[id]);
            if (linkedTags.any((tag) => tag == null)) {
              throw const FormatException(
                'O lançamento referencia um ID de tag inexistente.',
              );
            }
            tagsByEntry[entry.id] = linkedTags.cast<String>().toSet();
            if (entry.id.isEmpty ||
                entry.categoryId.isEmpty ||
                entry.amountCents <= 0)
              throw const FormatException('Lançamento inválido no CSV.');
            if (entries.containsKey(entry.id))
              throw const FormatException(
                'Há IDs de lançamento repetidos no CSV.',
              );
            entries[entry.id] = entry;
            break;
          case 'tag_catalogo':
            break;
          case 'categoria':
            break;
          case 'orcamento':
            final id = categoryId(row);
            final cents = money(row, 'limite_mensal');
            if (id.isEmpty || cents <= 0)
              throw const FormatException('Orçamento inválido no CSV.');
            budgets[id] = cents;
            break;
          case 'recorrencia':
            final linkedTags = value(row, 'tag_ids')
                .split(',')
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .map((id) => tagNamesById[id]);
            if (linkedTags.any((tag) => tag == null)) {
              throw const FormatException(
                'A recorrência referencia um ID de tag inexistente.',
              );
            }
            recurring.add(
              RecurringRule(
                id: value(row, 'id'),
                description: value(row, 'descricao'),
                amountCents: money(row, 'valor'),
                categoryId: categoryId(row),
                totalInstallments: integer(row, 'parcelas_total'),
                dayOfMonth: integer(row, 'dia_vencimento'),
                completedInstallments: integer(
                  row,
                  'parcelas_concluidas',
                  fallback: 1,
                ),
                nextDue: DateTime.parse(value(row, 'proximo_vencimento')),
                active: boolean(row, 'ativa', fallback: true),
                tags: linkedTags.cast<String>().toSet().toList(),
              ),
            );
            break;
          case '':
            continue;
          default:
            throw FormatException(
              'Tipo de linha desconhecido: ${value(row, 'tipo_registro')}',
            );
        }
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Há dados inválidos no CSV. Confira as colunas e os valores.',
      );
    }
    final entriesWithTags = entries.values
        .map(
          (entry) =>
              entry.copyWith(tags: (tagsByEntry[entry.id] ?? {}).toList()),
        )
        .toList();
    final categoryIds = {
      ...expenseCategories.map((category) => category.id),
      ...categories.map((category) => category.id),
    };
    if (tagsByEntry.keys.any((id) => !entries.containsKey(id)) ||
        entriesWithTags.any(
          (entry) => !categoryIds.contains(entry.categoryId),
        ) ||
        recurring.any(
          (rule) =>
              rule.id.isEmpty ||
              rule.amountCents <= 0 ||
              rule.totalInstallments < 2 ||
              rule.dayOfMonth < 1 ||
              rule.dayOfMonth > 31 ||
              rule.completedInstallments < 1 ||
              rule.completedInstallments > rule.totalInstallments ||
              !categoryIds.contains(rule.categoryId),
        ) ||
        budgets.keys.any((id) => !categoryIds.contains(id))) {
      throw const FormatException(
        'O CSV contém referências inválidas ou inconsistentes.',
      );
    }
    if (categories.map((category) => category.id).toSet().length !=
        categories.length) {
      throw const FormatException('Há IDs de categoria repetidos no CSV.');
    }
    return BackupData(
      entries: entriesWithTags,
      categories: categories,
      budgets: budgets,
      recurringRules: recurring,
      tags: {
        ...tagCatalog,
        ...entriesWithTags.expand((entry) => entry.tags),
      }.toList(),
    );
  }

  Future<void> restoreBackup(BackupData backup, {required bool merge}) async {
    if (!merge) {
      await saveAll(backup.entries);
      await saveCategories(backup.categories);
      await saveBudgets(backup.budgets);
      await saveRecurringRules(backup.recurringRules);
      await saveTags(backup.tags);
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
    await saveTags({...await loadTags(), ...backup.tags}.toList());
  }
}
