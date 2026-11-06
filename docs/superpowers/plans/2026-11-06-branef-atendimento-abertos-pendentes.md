# Conversas abertas e pendentes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mostrar conversas abertas e pendentes juntas no Atendimento da Branef, identificando o estado sem assumir o controle do bot ao visualizar.

**Architecture:** Acrescentar o filtro de consulta virtual `active` (open + pending) ao ConversationFinder e ao filtro do store. Usá-lo apenas na lista omnichannel do Atendimento, com paginação no servidor. Identificar o estado nos cartões dessa lista usando a apresentação existente; os estados persistidos e as ações de controle não mudam.

**Tech Stack:** Rails/ActiveRecord/PostgreSQL, Vue 3/Vuex, Vitest, RSpec, GitHub Actions/GHCR, Dokploy.

**Spec:** ../specs/2026-11-06-branef-atendimento-abertos-pendentes-design.md

## Global Constraints

- Conta Branef 3, caixa API 1; implantar somente na Branef.
- URA de teste permanece sem operações GLPI.
- Preservar filtros de responsável/canal, isolamento de conta/caixa, ENV, segredos, banco, Redis, S3 e NICO.
- Não modificar status, atribuição ou controle do robô ao visualizar uma conversa.
- `pending` não comprova que há robô ativo: usar rótulo Aguardando.
- Reutilizar o worktree isolado limpo existente; criar branch codex/branef-active-attendance-20261106 a partir do SHA de produção 4cdc9b7.

## Review Focus

- Resolvidos e adiados entre conversas recentes não consomem a paginação de ativos.
- Minhas não inclui pendentes sem atribuição; Todas continua restrito às permissões existentes.
- Transições open/pending permanecem visíveis, e resolved deixa a lista sem duplicação.
- Troca de conta e filtros não reapresenta resultados de outra conta.
- Selecionar cartão navega para o histórico sem alterar status, atribuição ou controle do bot. A marcação existente de última leitura é permitida.

### Task 1: Consulta paginada e filtragem de ativos

**Files:** app/finders/conversation_finder.rb; spec/finders/conversation_finder_spec.rb; app/javascript/dashboard/store/modules/conversations/helpers.js; testes existentes de helpers; documentação da API de listagem, se enumera status.

**Interfaces:** `ConversationFinder.new(user, status: 'active').perform` retorna somente open/pending na ordem e paginação atuais. `filterByStatus(chatStatus, 'active')` aceita exatamente open/pending; chamadas com open, pending e all conservam o comportamento anterior.

- [ ] Escrever regressões para ambos os estados, exclusão de resolved/snoozed, paginação e permissões de conta/caixa, além das consultas legadas.
- [ ] Executar testes direcionados e confirmar a falha para active na base atual.
- [ ] Implementar filtro de consulta virtual e filtro equivalente no store; atualizar contrato documentado se necessário, sem novo enum persistido.
- [ ] Executar RSpec de finder e Vitest de helpers e confirmar aprovação.

### Task 2: Lista e indicação visual de estado

**Files:** app/javascript/dashboard/routes/dashboard/inbox/InboxList.vue; InboxChannelGroups.vue; inboxPresentation.js; InboxList.spec.js; testes de grupos existentes.

**Interfaces:** Os filtros da consulta e `getAllStatusChats` usam active. Cartões da lista apresentam o texto de `conversationStateLabels` correspondente ao status, mantendo os eventos de seleção existentes.

- [ ] Acrescentar regressões que retornem e mostrem open/pending, excluam resolved/snoozed, preservem responsável/canal e atualização de estado, e provem navegação sem alteração de status/atribuição.
- [ ] Confirmar falhas dos testes novos antes da implementação.
- [ ] Atualizar lista e cartões sem alterar os componentes de resposta/assumir/retomar.
- [ ] Rodar suítes direcionadas de InboxList, InboxChannelGroups, HoyaInboxWorkspace e helpers; lint dos arquivos alterados; build frontend.
- [ ] Revisar o diff completo contra o desenho e registrar comandos/resultados.

### Task 3: Publicação e implantação autorizadas

**Files:** documentação de entrega e estado no output local; somente os arquivos de código/desenho/plano pertinentes no commit da branch.

- [ ] Publicar branch e acompanhar pipeline do mesmo SHA até imagem e gates aprovados; obter digest imutável.
- [ ] No Dokploy Branef, conferir imagem anterior e alterar somente JRC_IMAGE para o novo digest; redeploy e verificar serviços e saúde.
- [ ] Abrir Atendimento com filtro Todas no administrador, comprovar conversa de teste pendente na lista, abrir sem assumir e conferir que o robô permanece ativo.
- [ ] Registrar limites da homologação física: um caminho SISVISA observado; demais 59 opções cobertas pelo motor local, sem declarar todos os caminhos físicos aprovados.
- [ ] Entregar relatório, imagem anterior/nova, evidências e procedimento de retorno à imagem anterior preservando volumes.

## Execução

Implementação direta nesta sessão, dentro da autorização explícita para implementação, testes, publicação e implantação; nenhuma nova aprovação será exigida para as etapas já autorizadas.
