enum ExpenseSource { manual, autoRule, openFinance }

enum CategorizationMethod { manual, automatic }

class Expense {
  const Expense({
    required this.id,
    required this.amountCents,
    required this.description,
    required this.categoryId,
    required this.spentAt,
    this.categorySetAt,
    this.source = ExpenseSource.manual,
    this.categorizationMethod = CategorizationMethod.manual,
    this.recurrenceId,
    this.tags = const [],
    this.notes,
  });

  final String id;
  final int amountCents;
  final String description;
  final String categoryId;
  final DateTime spentAt;
  final DateTime? categorySetAt;
  final ExpenseSource source;
  final CategorizationMethod categorizationMethod;
  final String? recurrenceId;
  final List<String> tags;
  final String? notes;

  Map<String, Object?> toJson() => {
    'id': id,
    'amountCents': amountCents,
    'description': description,
    'categoryId': categoryId,
    'spentAt': spentAt.toIso8601String(),
    'categorySetAt': categorySetAt?.toIso8601String(),
    'source': source.name,
    'categorizationMethod': categorizationMethod.name,
    'recurrenceId': recurrenceId,
    'tags': tags,
    'notes': notes,
  };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    amountCents: json['amountCents'] as int,
    description: json['description'] as String,
    categoryId: json['categoryId'] as String,
    spentAt: DateTime.parse(json['spentAt'] as String),
    categorySetAt: json['categorySetAt'] == null
        ? null
        : DateTime.parse(json['categorySetAt'] as String),
    source: ExpenseSource.values.firstWhere(
      (value) => value.name == json['source'],
      orElse: () => ExpenseSource.manual,
    ),
    categorizationMethod: CategorizationMethod.values.firstWhere(
      (value) => value.name == json['categorizationMethod'],
      orElse: () => CategorizationMethod.manual,
    ),
    recurrenceId: json['recurrenceId'] as String?,
    tags: _decodeTags(json['tags']),
    notes: json['notes'] as String?,
  );

  Expense copyWith({
    int? amountCents,
    String? description,
    String? categoryId,
    DateTime? spentAt,
    DateTime? categorySetAt,
    ExpenseSource? source,
    CategorizationMethod? categorizationMethod,
    String? recurrenceId,
    List<String>? tags,
    String? notes,
  }) => Expense(
    id: id,
    amountCents: amountCents ?? this.amountCents,
    description: description ?? this.description,
    categoryId: categoryId ?? this.categoryId,
    spentAt: spentAt ?? this.spentAt,
    categorySetAt: categorySetAt ?? this.categorySetAt,
    source: source ?? this.source,
    categorizationMethod: categorizationMethod ?? this.categorizationMethod,
    recurrenceId: recurrenceId ?? this.recurrenceId,
    tags: tags ?? this.tags,
    notes: notes ?? this.notes,
  );
}

List<String> _decodeTags(Object? raw) {
  return (raw as List<dynamic>)
      .map((value) => value.toString())
      .toSet()
      .toList();
}

class ExpenseCategory {
  const ExpenseCategory(
    this.id,
    this.label,
    this.icon,
    this.colorValue, {
    this.archived = false,
    this.isCustom = false,
  });
  final String id;
  final String label;
  final String icon;
  final int colorValue;
  final bool archived;
  final bool isCustom;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'icon': icon,
    'colorValue': colorValue,
    'archived': archived,
    'isCustom': isCustom,
  };

  factory ExpenseCategory.fromJson(Map<String, dynamic> json) =>
      ExpenseCategory(
        json['id'] as String,
        json['label'] as String,
        json['icon'] as String? ?? 'more_horiz',
        json['colorValue'] as int? ?? 0xFF8D929B,
        archived: json['archived'] as bool? ?? false,
        isCustom: true,
      );
}

class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.description,
    required this.amountCents,
    required this.categoryId,
    required this.totalInstallments,
    required this.dayOfMonth,
    this.completedInstallments = 1,
    required this.nextDue,
    this.active = true,
    this.tags = const [],
  });

  final String id;
  final String description;
  final int amountCents;
  final String categoryId;
  final int totalInstallments;
  final int dayOfMonth;
  final int completedInstallments;
  final DateTime nextDue;
  final bool active;
  final List<String> tags;

  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'amountCents': amountCents,
    'categoryId': categoryId,
    'totalInstallments': totalInstallments,
    'dayOfMonth': dayOfMonth,
    'completedInstallments': completedInstallments,
    'nextDue': nextDue.toIso8601String(),
    'active': active,
    'tags': tags,
  };

  factory RecurringRule.fromJson(Map<String, dynamic> json) => RecurringRule(
    id: json['id'] as String,
    description: json['description'] as String,
    amountCents: json['amountCents'] as int,
    categoryId: json['categoryId'] as String,
    totalInstallments: json['totalInstallments'] as int,
    dayOfMonth: json['dayOfMonth'] as int,
    completedInstallments: json['completedInstallments'] as int? ?? 1,
    nextDue: DateTime.parse(json['nextDue'] as String),
    active: json['active'] as bool? ?? true,
    tags: _decodeTags(json['tags']),
  );

  RecurringRule copyWith({
    String? description,
    int? amountCents,
    String? categoryId,
    int? totalInstallments,
    int? dayOfMonth,
    int? completedInstallments,
    DateTime? nextDue,
    bool? active,
    List<String>? tags,
  }) => RecurringRule(
    id: id,
    description: description ?? this.description,
    amountCents: amountCents ?? this.amountCents,
    categoryId: categoryId ?? this.categoryId,
    totalInstallments: totalInstallments ?? this.totalInstallments,
    dayOfMonth: dayOfMonth ?? this.dayOfMonth,
    completedInstallments: completedInstallments ?? this.completedInstallments,
    nextDue: nextDue ?? this.nextDue,
    active: active ?? this.active,
    tags: tags ?? this.tags,
  );
}

const expenseCategories = <ExpenseCategory>[
  ExpenseCategory('food', 'Alimentação', 'restaurant', 0xFFE77B45),
  ExpenseCategory('home', 'Moradia', 'home', 0xFF6486C5),
  ExpenseCategory('transport', 'Transporte', 'directions_car', 0xFF55A69A),
  ExpenseCategory('health', 'Saúde', 'favorite', 0xFFD66B7A),
  ExpenseCategory('leisure', 'Lazer', 'movie', 0xFF9271C8),
  ExpenseCategory('shopping', 'Compras', 'shopping_bag', 0xFFE5AE48),
  ExpenseCategory('bills', 'Contas', 'receipt_long', 0xFF6B8F9F),
  ExpenseCategory('other', 'Outros', 'more_horiz', 0xFF8D929B),
];

ExpenseCategory categoryFor(
  String id, [
  List<ExpenseCategory> categories = expenseCategories,
]) => categories.firstWhere(
  (category) => category.id == id,
  orElse: () => expenseCategories.last,
);

String normalizeExpenseDescription(String description) => description
    .toLowerCase()
    .trim()
    .replaceAll(RegExp('[áàâãä]'), 'a')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôõö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

String? suggestCategoryFromHistory(
  String description, [
  List<Expense> history = const [],
  List<ExpenseCategory> categories = expenseCategories,
]) {
  final normalized = normalizeExpenseDescription(description);
  if (normalized.isEmpty) return null;
  final recentFirst = [...history]
    ..sort(
      (a, b) => (b.categorySetAt ?? b.spentAt).compareTo(
        a.categorySetAt ?? a.spentAt,
      ),
    );
  for (final expense in recentFirst) {
    if (normalizeExpenseDescription(expense.description) == normalized &&
        categories.any(
          (category) => category.id == expense.categoryId && !category.archived,
        )) {
      return expense.categoryId;
    }
  }
  return null;
}
