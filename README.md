# Controle de gastos

Aplicativo Flutter para acompanhar despesas pessoais no Android e na web.

## Recursos atuais

- Início com total e lançamentos recentes do mês.
- Cadastro, edição e exclusão de despesas.
- Categorias predefinidas e sugestões automáticas pela descrição.
- Filtro mensal e por categoria.
- Relatório de gastos por categoria.
- Dados guardados localmente no dispositivo ou navegador.

## Executar

```sh
flutter pub get
flutter run -d chrome
```

Para Android, selecione um emulador ou dispositivo conectado no lugar de `chrome`.

## Armazenamento

O MVP usa `shared_preferences` para guardar a lista de despesas em JSON. Os dados do navegador não são sincronizados com o Android. Limpar os dados do app ou do navegador pode apagá-los. Ainda não há exportação, backup ou conta.

## Próximas etapas

Consulte [o plano de evolução](docs/PLANO_DE_EVOLUCAO.md). A próxima entrega planejada é o widget Android de lançamento rápido.
