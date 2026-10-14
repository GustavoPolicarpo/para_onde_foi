# Plano revisado — GastoClaro

## Objetivo

Entregar um app pessoal para Android e web focado em registrar despesas e entender os gastos por mês, categoria e tags. O widget Android oferece cadastro rápido; Open Finance fica para uma fase futura.

## Estado atual do repositório

- O scaffold Flutter já existe em `lib/`, `android/` e `web/`; a tarefa não é mais criar o projeto.
- `lib/main.dart` e `README.md` já descrevem e implementam o produto, não o exemplo padrão do Flutter.
- O produto base, incluindo categorias, filtros, recorrências, orçamentos, relatórios e CSV, está implementado.
- O teste de widget que veio do scaffold ainda se refere ao contador de demonstração e precisa ser atualizado antes de usar a suíte.
- O widget Android mostra o total de despesas do mês e o progresso dos orçamentos, além de abrir o cadastro rápido de despesa.
- Não há backend nem integração financeira.

## Decisões de arquitetura

- **Cliente:** Flutter para Android e web.
- **Persistência atual do MVP:** `shared_preferences` com JSON versionado, por ser simples e compatível com Android e web. É adequado para o volume pequeno de um protótipo pessoal; não é a base ideal para histórico grande, consultas complexas ou transações. Migrar para Drift/SQLite quando esses requisitos surgirem. Armazenamento web e Android são locais e independentes; não há sincronização entre dispositivos.
- **Domínio:** armazenar dinheiro como inteiro em centavos, com moeda explícita (`BRL` inicialmente), data da despesa, descrição, categoria e origem. O escopo atual contém somente despesas.
- **Origem:** usar enum `manual`, `regraAutomatica` e `openFinance`. Uma regra automática descreve como categorizar um lançamento e pode classificar uma despesa manual ou importada; origem e método de classificação são conceitos diferentes.
- **Widget:** widget Android integrado ao app Flutter. Ele apresenta um resumo mensal e inicia o formulário rápido de despesa, que valida e grava o lançamento.
- **Backend:** nenhum para o MVP. Para Open Finance, o segredo do agregador fica no servidor; o app recebe token temporário de conexão.
- **Privacidade:** sem conta e sem envio de dados. O backup é manual; a troca entre Android e navegador depende de exportar e importar o arquivo.

## Escopo do MVP

1. Cadastro, edição e exclusão de despesa.
2. Categorias iniciais e escolha manual de categoria.
3. Regras automáticas simples por trecho de descrição, com prioridade determinística e possibilidade de correção manual.
4. Início com total do mês e despesas recentes.
5. Lista de despesas com filtro por mês e categoria.
6. Relatório mensal por categoria.
7. Persistência local em Android e web.

Sincronização, login, metas e Open Finance continuam fora do escopo atual. O app já inclui orçamento, recorrências, CSV e widget Android.

## Entregue nesta implementação

- Navegação responsiva entre Início, Despesas e Relatórios.
- Inclusão, edição e exclusão de despesas; valores são guardados em centavos.
- Categorias predefinidas e sugestão automática por palavras na descrição, com escolha manual disponível.
- Seletor de mês, filtro por categoria, resumo mensal e totais por categoria.
- Persistência local via `shared_preferences` em Android e web.
- Categorias editáveis/arquiváveis, busca e filtros, recorrências confirmadas pelo usuário, orçamentos mensais e importação/exportação CSV.

## Próximas tarefas, em ordem

### 1. Substituir o app de demonstração pelo esqueleto do produto — concluída

- Definir navegação e adaptação para tela pequena e larga.
- Criar as três áreas previstas: Início, Despesas e Relatórios.
- Criar tema, estados vazios e fluxo visual de adicionar despesa.
- Critério de conclusão: navegar entre as áreas e abrir o formulário de despesa em Android e web.

### 2. Fazer a prova técnica de persistência nos dois alvos — substituída no MVP

- O MVP usa `shared_preferences` com JSON, sem tabela SQL nem arquivos WASM.
- Avaliar Drift quando o volume de dados, relatórios e regras de consistência ultrapassar o escopo de um armazenamento chave-valor.

### 3. Implementar domínio e cadastro de despesas — concluída

- Modelar despesa, categoria, moeda, origem e timestamps.
- Implementar CRUD, validação de valor/data e formatação em BRL na interface.
- Definir exclusão/edição e como tratar categorias removidas que já tenham despesas.
- Critério de conclusão: lançar, editar, excluir e reabrir despesas persistidas.

### 4. Implementar regras de categoria e consultas — versão inicial concluída

- Modelar regras por palavra ou trecho normalizado, com ordem/prioridade explícita.
- Permitir corrigir a categoria sugerida e preservar a escolha manual.
- Construir consultas para total mensal, recentes, filtros e totais por categoria.
- Critério de conclusão: os mesmos dados produzem resultados coerentes em Android e web.

### 5. Fechar o MVP de telas e revisar o fluxo — versão inicial concluída

- Conectar Início, Despesas e Relatórios ao repositório.
- Tratar estados sem dados, erros de armazenamento e meses sem despesas.
- Revisar acessibilidade básica e layouts estreitos/largos.
- Critério de conclusão: fluxo completo sem dados fictícios do template.

### 6. Completar as funções do produto base — concluída

- **Controle de despesas:** resumir gastos por mês e acompanhar totais por categoria, mantendo o cadastro focado em despesas.
- **Categorias próprias:** criar, renomear, arquivar e escolher ícone/cor; impedir que despesas existentes percam sua categoria.
- **Busca e filtros:** pesquisar descrição e filtrar por intervalo de datas, categoria e tipo.
- **Recorrências:** definir periodicidade e próxima ocorrência, com revisão clara antes de criar lançamentos futuros.
- **Orçamento:** definir teto mensal por categoria e mostrar valor usado e restante.
- **Exportação/backup:** exportar e importar os dados antes de oferecer continuidade entre dispositivos; validar arquivo e evitar duplicatas na importação.
- Critério de conclusão: o uso diário do app não depende do widget e os dados podem ser recuperados pelo usuário.

Implementado nesta etapa: categorias personalizáveis/arquiváveis, busca e filtros por período/categoria/tags, recorrências com confirmação manual, limites mensais por categoria e importação/exportação CSV.

### 7. Planejar e construir o widget Android — concluída

- Prototipar Glance em uma pasta/módulo Android e validar instalação/manifesto no projeto atual.
- Definir o contrato de entrada rápida: valor e categoria opcionais; abrir o app para completar descrição/data quando necessário.
- Reutilizar a validação e as regras do fluxo principal; o widget só acelera a entrada.
- Definir passagem segura do rascunho para o fluxo Flutter e atualização do widget após salvar.
- Critério de conclusão: adicionar um gasto pelo widget e vê-lo no app sem duplicidade; todas as funções do app continuam disponíveis sem ele.

### Próxima etapa

- Avaliar melhorias de usabilidade no cadastro rápido e nos insights de gastos. A integração Open Finance permanece posterior e depende de uma avaliação de provedores, custos e requisitos de backend.

### 8. Evoluções posteriores

- **Open Finance:** escolher agregador (Pluggy ou Belvo), confirmar custos, requisitos contratuais e cobertura bancária; construir backend para segredo e token curto; consentimento, importação idempotente, reconciliação de duplicatas, revogação e exclusão de dados.
- **Planejamento:** metas e projeções somente após haver histórico confiável e importação revisada.

## Dependências e riscos a resolver

- Persistência Drift na web exige configuração e teste de implantação específicos; não presumir equivalência perfeita com SQLite nativo.
- O armazenamento local em JSON não sincroniza Android com navegador e pode ser perdido ao limpar dados do app/browser. O backup exportado deve ser copiado para um local seguro pelo usuário.
- Widget Glance roda fora do ciclo normal de telas Flutter. Validar o caminho de handoff cedo, antes de investir na UI final do widget.
- Agregadores e SDKs podem mudar disponibilidade, preço e suporte. Reavaliar quando a fase de Open Finance for priorizada.

## Referências técnicas

- [Drift — suporte web](https://drift.simonbinder.eu/platforms/web/)
- [Android Developers — criar widget com Glance](https://developer.android.com/develop/ui/compose/glance/create-app-widget)
- [Android Developers — estado e ciclo de vida do GlanceAppWidget](https://developer.android.com/develop/ui/compose/glance/glance-app-widget)
- [Pacote glance_widget no pub.dev](https://pub.dev/packages/glance_widget) — avaliar versão e compatibilidade no momento da implementação; não assumir o pacote como dependência antes do protótipo.
