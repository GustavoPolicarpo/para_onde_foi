# Para Onde Foi

Aplicativo Flutter para acompanhar despesas pessoais no Android e na web.

## Recursos atuais

- Início com total e lançamentos recentes do mês.
- Cadastro, edição e exclusão de despesas.
- Categorias predefinidas e sugestão baseada na última categoria usada para a mesma descrição.
- Categorias personalizadas, com opção de arquivar sem perder o histórico.
- Busca e filtros por data, categoria e tags.
- Parcelas mensais automáticas, processadas ao abrir o app ou atualizar a página.
- Notas opcionais em cada despesa, incluídas no CSV.
- Limite mensal por categoria e valor restante.
- Relatório de gastos por categoria.
- Dados guardados localmente no dispositivo ou navegador.
- Exportação e importação em CSV para editar os dados em planilhas.
- Widget Android com resumo mensal e cadastro rápido de despesas.

## Executar

```sh
flutter pub get
flutter run -d chrome
```

Para Android, selecione um emulador ou dispositivo conectado no lugar de `chrome`.

## Armazenamento

O app usa `shared_preferences` para guardar os dados localmente. Android e navegador mantêm cópias independentes, sem sincronização. Exporte o CSV regularmente; limpar dados do app ou do navegador pode apagá-los.

## Próximas etapas

Consulte [o plano de evolução](docs/PLANO_DE_EVOLUCAO.md) para as próximas etapas.
