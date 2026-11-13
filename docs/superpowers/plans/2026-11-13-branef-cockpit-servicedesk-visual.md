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

- [x] Testar configuração por conta em `temporaryVisibility.spec.js`, preservação dos defaults e atalhos equivalentes.
- [x] `temporaryVisibility.js`, `Sidebar.vue`, `layout/useQuickActionAccess.js`: Cockpit antes de Inbox; visibilidade por `custom_attributes.jrc_navigation.hidden_entries`; serializar somente chave necessária no `_account.json.jbuilder`.
- [x] `JrcAi::CockpitTicketMetrics` como ponto de extensão neutro; `CockpitMetricsService` inclui `ticket_metrics`, sem amostra de espera retorna null. Testes de provider/período e nulidade.
- [x] `TicketMetricsCard.vue` no Cockpit, estados explícitos e rota/período do servidor. Proteger requisições concorrentes e limpeza na troca de conta.
- [x] Validar testes/frontend lint; commit local do núcleo e integrar seletivamente esse incremento à Branef.

## Task 2 — Branef: adaptador GLPI

- [x] Testar fonte nativa/sem acesso, leitura permitida, período, zero/indisponível/parcial, erro e ausência de chamadas remotas.
- [x] `JrcServiceDesk::Glpi::CockpitMetrics` e initializer registram provider neutro; `Overview.selection`/Report existentes fornecem agregado autorizado. Usar política `report?`, contexto autenticado e conexão habilitada como origem GLPI.
- [x] Resposta com source, state, total, active, exceeded, coverage, collected_at, filters, timezone e rota neutra. Não expor metadados de outros operadores.
- [x] Contexto GLPI expõe fuso configurado para formatação de datas sem offset.
- [x] Verificar em PostgreSQL/Rails isolados; commit local.

## Task 3 — Branef: visual compartilhado

- [x] Testes comportamentais de filtros/chips/limpeza, escape de entidades, timezone e agrupamento de erros; preservar testes atuais.
- [x] Helpers de apresentação + `GlpiBadge.vue`, `GlpiFilters.vue`, `GlpiCoverage.vue`: cores semânticas, rótulos, foco, filtros aplicados/URL, compactação com detalhes de cobertura.
- [x] `GlpiServiceDesk.vue`, `GlpiSync.vue`: títulos por tela, erros agrupados com operação e detalhe, coleta administrativa em detalhes expansíveis.
- [x] `GlpiTicketWorkspace.vue`, `GlpiOverview.vue`, `GlpiResourceBoard.vue`, formulários: painéis, tabela, status/prioridade, nomes e datas legíveis, gráficos com valores e legendas, sem alterar ações/permissões/exportação.
- [x] Matriz de rotas: glpi/tickets/mine/incidents/detail/edit/new; overview/reports/sla; queues/assignees/catalog/knowledge/tasks/approvals/problems/changes/assets/documents/surveys; telas locais/governança/gestão conservam rotas e controles, recebem hierarquia do layout comum.
- [x] Vitest de origem, operações, filtros e regressões, lint e build. Conferência visual desktop/estreita/teclado, dados sintéticos marcados. Commit local.

## Task 4 — revisão e entrega local

- [x] Revisão independente do diff conjunto, corrigir achados importantes com testes.
- [x] Verificação final adequada, diff/check/clean, relatar separadamente código/testes/build e produção não implantada.
- [x] Registrar instrução futura para configurar Calling na conta escolhida; não aplicar alteração de ambiente agora.

## Roteiro de testes

Vitest via Node 24 e dependências existentes; suítes dos arquivos alterados e contratos GLPI, sem cache/coverage. Rails em containers descartáveis próprios com PostgreSQL pgvector/Redis e rede interna; nenhum endpoint de cliente. Lint dos arquivos tocados e build Vite nas revisões finais. Resultados e limites ficam no relatório de entrega.

## Execução local concluída — 13/11/2026

Código: b0d5a4bd6c498638a7e01ffd00ce6f40ec2b08b7. Núcleo: 05bc5999d5bc25ba4454a0cd614a8ab7cde1947f.
Frontend: 120/120; reexecução GLPI após responsividade: 113/113; Rails: 13/13. Build Vite final aprovado. Lint dos 24 arquivos JS/Vue: zero erros, 61 avisos registrados; três arquivos Ruby novos sem infrações.
Revisão independente apontou fuso e URL da lixeira; ambos corrigidos por RED→GREEN. QA corrigiu vazio/indisponível e largura intrínseca da paginação. Componentes reais com transporte sintético conferidos em 320 e 390 px, claro/escuro e teclado, sem erros JS.
Melhoria menor adiada: nomes acessíveis das barras de status/prioridade ainda mostram códigos numéricos; rótulos e contagens visíveis estão disponíveis.
O teste legado suplementar foi interrompido por ausência de resposta do Docker local após falta de espaço. Sua execução e a limpeza dos três containers descartáveis não foram confirmadas; não foram reiniciados outros containers.
Não houve push, CI, imagem publicada, deploy, escrita GLPI real ou alteração de credenciais/URA/NICO/permissões. Publicação e aceitação operacional permanecem fora desta etapa. A configuração por conta para ocultar Calling está preparada no relatório; não foi aplicada no ambiente.
Rulings: no Windows, registros diretos substituíram o helper Bash (sem resumo automático); QA visual feita pelo executor (sem avaliação visual independente); produção fora do escopo autorizado (sem comprovação operacional).
Evidências e passos futuros: output/implementacao-visual-20261113 no diretório de coordenação JRCBranef.
