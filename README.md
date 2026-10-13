# Controle de gastos

Aplicativo Flutter para acompanhar despesas pessoais no Android e na web.

## Recursos atuais

- Início com total e lançamentos recentes do mês.
- Cadastro, edição e exclusão de receitas e despesas.
- Categorias predefinidas e sugestões automáticas pela descrição.
- Categorias personalizadas, com opção de arquivar sem perder o histórico.
- Busca, filtros por data, categoria e tipo.
- Recorrências semanais, mensais ou anuais, sempre confirmadas antes de lançar.
- Limite mensal por categoria e valor restante.
- Relatório de gastos por categoria.
- Dados guardados localmente no dispositivo ou navegador.
- Exportação e importação de backup JSON, com mesclagem ou substituição.

## Executar

```sh
flutter pub get
flutter run -d chrome
```

Para Android, selecione um emulador ou dispositivo conectado no lugar de `chrome`.

## Armazenamento

O app usa `shared_preferences` para guardar os dados em JSON. Android e navegador mantêm cópias locais independentes, sem sincronização. Exporte backups regularmente; limpar dados do app ou do navegador pode apagá-los.

## Próximas etapas

Consulte [o plano de evolução](docs/PLANO_DE_EVOLUCAO.md). A próxima entrega planejada é o widget Android de lançamento rápido, depois da consolidação do produto base.
