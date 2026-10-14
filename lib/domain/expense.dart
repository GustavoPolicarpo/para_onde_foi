enum ExpenseSource { manual, autoRule, openFinance }

enum CategorizationMethod { manual, automatic }

enum RecurrenceFrequency { weekly, monthly, yearly }

class Expense {
  const Expense({
    required this.id,
    required this.amountCents,
    required this.description,
    required this.categoryId,
    required this.spentAt,
    this.source = ExpenseSource.manual,
    this.categorizationMethod = CategorizationMethod.manual,
    this.recurrenceId,
    this.tags = const [],
  });

  final String id;
  final int amountCents;
  final String description;
  final String categoryId;
  final DateTime spentAt;
  final ExpenseSource source;
  final CategorizationMethod categorizationMethod;
  final String? recurrenceId;
  final List<String> tags;

  Map<String, Object?> toJson() => {
    'id': id,
    'amountCents': amountCents,
    'description': description,
    'categoryId': categoryId,
    'spentAt': spentAt.toIso8601String(),
    'source': source.name,
    'categorizationMethod': categorizationMethod.name,
    'recurrenceId': recurrenceId,
    'tags': tags,
  };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    amountCents: json['amountCents'] as int,
    description: json['description'] as String,
    categoryId: json['categoryId'] as String,
    spentAt: DateTime.parse(json['spentAt'] as String),
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
  );

  Expense copyWith({
    int? amountCents,
    String? description,
    String? categoryId,
    DateTime? spentAt,
    ExpenseSource? source,
    CategorizationMethod? categorizationMethod,
    String? recurrenceId,
    List<String>? tags,
  }) => Expense(
    id: id,
    amountCents: amountCents ?? this.amountCents,
    description: description ?? this.description,
    categoryId: categoryId ?? this.categoryId,
    spentAt: spentAt ?? this.spentAt,
    source: source ?? this.source,
    categorizationMethod: categorizationMethod ?? this.categorizationMethod,
    recurrenceId: recurrenceId ?? this.recurrenceId,
    tags: tags ?? this.tags,
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
    required this.frequency,
    required this.nextDue,
    this.active = true,
  });

  final String id;
  final String description;
  final int amountCents;
  final String categoryId;
  final RecurrenceFrequency frequency;
  final DateTime nextDue;
  final bool active;

  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'amountCents': amountCents,
    'categoryId': categoryId,
    'frequency': frequency.name,
    'nextDue': nextDue.toIso8601String(),
    'active': active,
  };

  factory RecurringRule.fromJson(Map<String, dynamic> json) => RecurringRule(
    id: json['id'] as String,
    description: json['description'] as String,
    amountCents: json['amountCents'] as int,
    categoryId: json['categoryId'] as String,
    frequency: RecurrenceFrequency.values.firstWhere(
      (v) => v.name == json['frequency'],
      orElse: () => RecurrenceFrequency.monthly,
    ),
    nextDue: DateTime.parse(json['nextDue'] as String),
    active: json['active'] as bool? ?? true,
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

String? suggestCategory(
  String description, [
  List<ExpenseCategory> categories = expenseCategories,
]) {
  final text = description.toLowerCase();
  const rules = <String, List<String>>{
    'food': [
      'mercado',
      'supermercado',
      'restaurante',
      'ifood',
      'padaria',
      'café',
      'lanche',
    ],
    'transport': [
      'uber',
      '99',
      'combustível',
      'gasolina',
      'posto',
      'metrô',
      'onibus',
      'ônibus',
    ],
    'home': [
      'aluguel',
      'condomínio',
      'condominio',
      'energia',
      'água',
      'internet',
    ],
    'health': [
      'farmácia',
      'farmacia',
      'médico',
      'medico',
      'consulta',
      'academia',
    ],
    'leisure': ['cinema', 'show', 'viagem', 'jogo', 'streaming'],
    'shopping': ['loja', 'roupa', 'amazon', 'compra'],
    'bills': ['fatura', 'conta', 'telefone', 'luz'],
  };
  for (final entry in rules.entries) {
    if (entry.value.any(text.contains) &&
        categories.any(
          (category) => category.id == entry.key && !category.archived,
        )) {
      return entry.key;
    }
  }
  return null;
}
