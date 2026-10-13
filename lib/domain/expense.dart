enum ExpenseSource { manual, autoRule, openFinance }

enum CategorizationMethod { manual, automatic }

class Expense {
  const Expense({
    required this.id,
    required this.amountCents,
    required this.description,
    required this.categoryId,
    required this.spentAt,
    this.source = ExpenseSource.manual,
    this.categorizationMethod = CategorizationMethod.manual,
  });

  final String id;
  final int amountCents;
  final String description;
  final String categoryId;
  final DateTime spentAt;
  final ExpenseSource source;
  final CategorizationMethod categorizationMethod;

  Map<String, Object?> toJson() => {
    'id': id,
    'amountCents': amountCents,
    'description': description,
    'categoryId': categoryId,
    'spentAt': spentAt.toIso8601String(),
    'source': source.name,
    'categorizationMethod': categorizationMethod.name,
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
  );
}

class ExpenseCategory {
  const ExpenseCategory(this.id, this.label, this.icon, this.colorValue);
  final String id;
  final String label;
  final String icon;
  final int colorValue;
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

ExpenseCategory categoryFor(String id) => expenseCategories.firstWhere(
  (category) => category.id == id,
  orElse: () => expenseCategories.last,
);

String? suggestCategory(String description) {
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
    if (entry.value.any(text.contains)) return entry.key;
  }
  return null;
}
