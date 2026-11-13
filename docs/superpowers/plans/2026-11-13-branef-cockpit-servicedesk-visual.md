# Cockpit e Service Desk — implementação

> For agentic workers: use superpowers:executing-plans. Executar nesta sessão; revisão independente final conforme a skill. Implementação e testes aprovados; publicação e implantação excluídas desta etapa.

**Goal:** Cockpit primeiro, visibilidade de Calling por conta, card de chamados autorizado e Service Desk legível, preservando regras e integrações.
**Architecture:** núcleo LAB2 oferece extensão neutra de indicadores; Branef implementa o adaptador GLPI sobre a projeção já autorizada. Componentes Vue compartilhados preservam rotas e contratos existentes.
**Tech Stack:** Rails, PostgreSQL, Vue 3, Tailwind, Vitest, RSpec.
**Spec:** `docs/superpowers/specs/2026-11-13-branef-cockpit-servicedesk-visual-design.md` (aprovado em 13/11).

## Global Constraints

- Bases: núcleo d8a83b824b11cc68ddbbce7c79681f368051fb70; Branef d1b47c944f5c44eb73f13c0793b79ce83c4f360a. Worktrees geridas pelo Codex.
- Sem alteração de URA, Broker, NICO, credenciais, agentes, times, permissões ou dados reais. Sem push/deploy.
- Configuração de apresentação não concede autorização. Núcleo não conhece GLPI/Branef; defaults preservam outros clientes.
- Card usa projeção local, política e entidades do operador, período de abertura explícito. Sem coleta remota automática. Indisponível não vira zero.
- Tailwind e i18n do projeto; novas strings apenas namespace en. Sem HTML remoto executável.
- Testes isolados com dados sintéticos; reaproveitar dependências instaladas sem modificar checkout original.

## Review Focus

Conferir: troca de conta/usuário durante requisição; escopo de operador restrito e identidade não mapeada; ausência de projeção versus zero; cobertura parcial e timestamp; datas GLPI sem offset e fuso explícito; filtros em URL e exportação com recibo independente; Calling escondido somente pela configuração da conta; catálogo recusado preserva erro; nenhuma extensão GLPI no núcleo.

## Task 1 — Núcleo: navegação e contrato neutro

- [ ] Testar configuração por conta em `temporaryVisibility.spec.js`, preservação dos defaults e atalhos equivalentes.
- [ ] `temporaryVisibility.js`, `Sidebar.vue`, `layout/useQuickActionAccess.js`: Cockpit antes de Inbox; visibilidade por `custom_attributes.jrc_navigation.hidden_entries`; serializar somente chave necessária no `_account.json.jbuilder`.
- [ ] `JrcAi::CockpitTicketMetrics` como ponto de extensão neutro; `CockpitMetricsService` inclui `ticket_metrics`, sem amostra de espera retorna null. Testes de provider/período e nulidade.
- [ ] `TicketMetricsCard.vue` no Cockpit, estados explícitos e rota/período do servidor. Proteger requisições concorrentes e limpeza na troca de conta.
- [ ] Validar testes/frontend lint; commit local do núcleo e integrar seletivamente esse incremento à Branef.

## Task 2 — Branef: adaptador GLPI

- [ ] Testar fonte nativa/sem acesso, leitura permitida, período, zero/indisponível/parcial, erro e ausência de chamadas remotas.
- [ ] `JrcServiceDesk::Glpi::CockpitMetrics` e initializer registram provider neutro; `Overview.selection`/Report existentes fornecem agregado autorizado. Usar política `report?`, contexto autenticado e conexão habilitada como origem GLPI.
- [ ] Resposta com source, state, total, active, exceeded, coverage, collected_at, filters, timezone e rota neutra. Não expor metadados de outros operadores.
- [ ] Contexto GLPI expõe fuso configurado para formatação de datas sem offset.
- [ ] Verificar em PostgreSQL/Rails isolados; commit local.

## Task 3 — Branef: visual compartilhado

- [ ] Testes comportamentais de filtros/chips/limpeza, escape de entidades, timezone e agrupamento de erros; preservar testes atuais.
- [ ] Helpers de apresentação + `GlpiBadge.vue`, `GlpiFilters.vue`, `GlpiCoverage.vue`: cores semânticas, rótulos, foco, filtros aplicados/URL, compactação com detalhes de cobertura.
- [ ] `GlpiServiceDesk.vue`, `GlpiSync.vue`: títulos por tela, erros agrupados com operação e detalhe, coleta administrativa em detalhes expansíveis.
- [ ] `GlpiTicketWorkspace.vue`, `GlpiOverview.vue`, `GlpiResourceBoard.vue`, formulários: painéis, tabela, status/prioridade, nomes e datas legíveis, gráficos com valores e legendas, sem alterar ações/permissões/exportação.
- [ ] Matriz de rotas: glpi/tickets/mine/incidents/detail/edit/new; overview/reports/sla; queues/assignees/catalog/knowledge/tasks/approvals/problems/changes/assets/documents/surveys; telas locais/governança/gestão conservam rotas e controles, recebem hierarquia do layout comum.
- [ ] Vitest de origem, operações, filtros e regressões, lint e build. Conferência visual desktop/estreita/teclado, dados sintéticos marcados. Commit local.

## Task 4 — revisão e entrega local

- [ ] Revisão independente do diff conjunto, corrigir achados importantes com testes.
- [ ] Verificação final adequada, diff/check/clean, relatar separadamente código/testes/build e produção não implantada.
- [ ] Registrar instrução futura para configurar Calling na conta escolhida; não aplicar alteração de ambiente agora.

## Roteiro de testes

Vitest via Node 24 e dependências existentes; suítes dos arquivos alterados e contratos GLPI, sem cache/coverage. Rails em containers descartáveis próprios com PostgreSQL pgvector/Redis e rede interna; nenhum endpoint de cliente. Lint dos arquivos tocados e build Vite nas revisões finais. Resultados e limites ficam no relatório de entrega.
