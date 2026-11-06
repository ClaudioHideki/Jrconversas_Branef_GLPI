# Branef URA Documental e GLPI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar os quatro sistemas e fluxos documentais da Branef, do WhatsApp à entrega auditada no GLPI, com homologação isolada.

**Architecture:** Flow/Broker executa triagem e transporte; catálogo versionado e regras pertencem ao JRC. Uma variante tipada do protocolo domain registra uma demanda durável no JRC; jobs fora da transação de conversa executam GLPI e o Flow consulta o resultado. GLPI permanece origem oficial, com vinculação local e sem Ticket nativo duplicado.

**Tech Stack:** Rails/ActiveRecord/PostgreSQL/Sidekiq; Vue; TypeScript/Zod/React/Vitest do Broker; motor Flow existente; GLPI isolado para escrita.

**Spec:** docs/superpowers/specs/2026-11-06-branef-ura-documentos-glpi-design.md

## Global Constraints

- Conta de destino Branef 3; nenhum ID fixo de cliente no código genérico. Sem alterações Grupo JRC/LAB.
- Teste Welton sem criar/alterar chamados reais; destinos de escrita somente laboratório sintético.
- Referência SLA: Proposta - Nova árvore com exceções Maringá; conservar unidade original até mapear calendário/finalidade GLPI.
- Dois modos de abertura; N2/N3 conjunto até regra específica; 48 horas corridas após aviso entregue, cancelamento por resposta e sem pesquisa nesse resultado.
- Credenciais só no runtime protegido; documentos, lista pessoal e mensagens reais fora do Git; efeitos reais excluídos não são autorizados por anexos.
- Recurso opt-in, capacidades/revisões verificadas; nenhuma regressão de CRM, transporte e origem nativa.
- Executar nesta sessão pelo método nativo já utilizado; uma revisão independente da branch ao final. Não reabrir autorização por tarefa.

## Review Focus

- Retomada ou publicação nova do Flow não pode gerar segundo ticket do mesmo episódio (Task 3).
- Mensagem recebida em disputa com job de 48h cancela a ação quando a entrada é mais recente (Task 5).
- Falha após criação mas antes de atribuir grupo/SLA conserva protocolo e não anuncia fila confirmada (Task 3).
- Regras de município e perfil declarado não concedem consulta a chamados de terceiros (Tasks 1/2/4).
- Motor/binding suportado com backend antigo ou configuração revogada não executa operação nova nem altera CRM existente (Task 4).

---

## Estrutura e unidades

JRC: reutilizar worktree .private/branef-glpi-integral (base 3d82f486, branch codex/branef-ura-documentos-20261106); Broker: .private/broker-branef-ura-documentos (base 2d30a5a5, mesma branch). O primeiro já é worktree isolado; a criação nativa do segundo não reconheceu o checkout, sendo usado fallback Git sob a raiz gravável.

Diretório lógico JRC `app/services/jrc_service_desk/intake/`: `catalogue.rb` (catálogo), `input.rb` (identificação/triagem), `submission.rb` (episódio), `delivery.rb` (executor GLPI), `pending_information.rb` (prazo), `notification.rb` (entrega/satisfação). Evitar um serviço único que mistura conversa, rede, dados e agendamento.

Configuração e conteúdo Branef: artefatos locais `output/BRANEF-ATENDIMENTO-CATALOGO.json`, `BRANEF-RESPOSTAS-DOCUMENTAIS.json` e `BRANEF-URA-DOCUMENTAL-TESTE.json`, carregados por configuração autenticada; não incorporar dados pessoais ao build.

### Task 1: Catálogo, classificação e conteúdo documental

**Files:** Create JRC `app/services/jrc_service_desk/intake/catalogue.rb`, `input.rb`; Test `test/jrc_service_desk/intake_catalogue_test.rb`; Create compilador local `.private/build_branef_documental_catalogue.py`.

**Interfaces:** `Catalogue.new(document)` valida revisão e estrutura; `classify(system:, location:, reason:, subject:, profile:)` retorna códigos, fila lógica e prazo original; `Input.new(catalogue).call(attributes)` retorna triagem normalizada sem IDs remotos. Catálogo usa códigos imutáveis e labels, localização independente, lista exata de submotivos por sistema/motivo, fila e regra de SLA por motivo/local. Respostas têm condições, fonte, texto e hyperlinks, além de flag de confirmação humana quando afirmam fatos externos.

- [ ] Escrever `test_classifies_municipality_exception_without_cross_row_inference`, `test_rejects_unknown_combination_and_placeholder`, `test_preserves_days_and_no_deadline`, `test_declared_profile_does_not_authorize_lookup`; verificar resultado de regra específica sobre geral e erros de catálogo, não apenas contagem.
- [ ] Rodar `bundle exec ruby test/jrc_service_desk/intake_catalogue_test.rb`: RED por classe ausente.
- [ ] Implementar catálogo puro e input estrito: um motivo/classificação, campos limitados, CPF/CNPJ sem exposição em logs/títulos e e-mail validado. Não atribuir identidade autenticada a formato válido.
- [ ] Gerar artefatos privados a partir dos arquivos lidos; conferir quatro sistemas, 65 submotivos, 8 hyperlinks Notion, todas as condições Maringá e modelos de 48h/satisfação/JIRA. Repetições no DOCX não geram respostas duplicadas; placeholders exigem parâmetros.
- [ ] Rodar teste e auditoria privada fontes→artefatos; GREEN, nenhum original alterado. Commit `feat(service-desk): validate versioned intake catalogues` somente código e fixtures sintéticas.

### Task 2: Configuração publicada e demanda durável

**Files:** Create migration `db/migrate/20261106180000_create_service_desk_intake.rb`, models `app/models/jrc_service_desk/intake_configuration.rb`, `intake_demand.rb`; Create services `intake/submission.rb`, controller `app/controllers/api/v1/accounts/jrc_service_desk/intake_controller.rb`, policy `app/policies/jrc_service_desk/intake_configuration_policy.rb`; Modify `config/routes.rb`; Test `test/jrc_service_desk/intake_submission_integration.rb`.

**Interfaces:** IntakeConfiguration: account, inbox, revision, catalogue, mappings, mode, enabled, remote_writes_enabled; revisões publicadas imutáveis, uma ativa por caixa. IntakeDemand: account/conversation/contact/inbox, UUID de episódio, revisão fixada, ator de serviço, entrada cifrada, fingerprint, estado/recibos e referência remota; dados pessoais não expostos na resposta pública. `Submission.call(authority:, conversation:, arguments:)` cria/reutiliza demanda e devolve `{id, state, created}` sem rede. UUID estável da operação de início fica persistido e é reutilizado pelo status; nova demanda exige início explícito.

- [ ] RED: `test_same_episode_reuses_row`, `test_incompatible_retry_is_conflict`, `test_new_explicit_episode_can_create_another_demand`, `test_cross_account_or_inbox_is_denied`, `test_published_revision_is_immutable`, `test_no_glpi_request_inside_submission`.
- [ ] Rodar `bundle exec ruby test/jrc_service_desk/intake_submission_integration.rb`, confirmar ausência de recurso e não erro de setup.
- [ ] Criar tabelas e constraints compostas; cifrar input; validar associação ativa conta/caixa/conversa/contato e identidade operacional; publicar só catálogo válido. Conservar mapeamentos pendentes claramente, bloqueando escrita real até ficar pronto.
- [ ] Expor GET/configuração e publicação administrativa, POST prévia/triagem e GET estado por conversa, com whitelist e projeção sem PII. Conta/caixa vêm do contexto autenticado.
- [ ] GREEN com migração em banco sintético, regressão do módulo; commit `feat(service-desk): persist scoped intake demands`.

### Task 3: Entrega GLPI, fila, SLA e recibos parciais

**Files:** Create `app/jobs/jrc_service_desk/intake_delivery_job.rb`, `app/services/jrc_service_desk/intake/delivery.rb`; Modify `glpi/operation_catalogue.rb`, `glpi/command_input.rb`, `glpi/resource_query.rb` somente para operações/catálogos necessários; Test `test/jrc_service_desk/intake_delivery_integration.rb`, `test/glpi_lab/intake_application.rb`.

**Interfaces:** `Delivery.call(demand_id:)` usa configuração fixada, autoridade novamente validada e `Glpi::AutomationCommand`; estágios `ticket`, `link`, `assignment`, `sla`. Job roda depois do commit. Estados `qualified`, `queued`, `sending`, `confirmed`, `partial`, `rejected`, `indeterminate`, `test_only`; receipt informa estágio e remote_id somente quando confirmado. Mapeamentos incluem conexão/revisão, entidade, categoria, solicitante, grupo e SLA/calendário/finalidade conferidos na origem. Campos GLPI novos só após validar no laboratório/contrato da versão suportada.

- [ ] RED: `test_disabled_real_writes_never_constructs_client`, `test_republish_and_retry_keep_original_episode_key`, `test_group_failure_preserves_created_ticket`, `test_timeout_after_create_is_not_replayed`, `test_sla_calendar_mismatch_blocks_assignment`, `test_revoked_actor_or_binding_blocks_job`.
- [ ] Rodar `bundle exec ruby test/jrc_service_desk/intake_delivery_integration.rb`.
- [ ] Implementar fora da transação de conversa; confirmar origem por estágio, persistir intenção e reusar idempotência de cada etapa. Sem requester mapeado não substituir cliente pelo usuário técnico. Usar vínculo remoto existente sem criar Ticket local.
- [ ] Exercitar contra GLPI isolado criação→atribuição→SLA→leitura e falhas parciais. Descobrir direitos reais separadamente; sem métodos/IDs arbitrários recebidos do Flow.
- [ ] GREEN; commit `feat(service-desk): deliver intake with audited GLPI receipts`.

### Task 4: Comando tipado Broker↔JRC e editor

**Files JRC:** Modify `app/services/jrc_domain_commands/request.rb`, `apply.rb`, `scope.rb`, `app/controllers/api/v1/accounts/jrc_domain_commands_controller.rb`; Test `test/jrc_service_desk/intake_broker_protocol_integration.rb`.

**Files Broker:** Modify `packages/contracts/src/automation-domain-command.ts`, `automation-conversation-effects.ts`, `apps/api/src/modules/automations/conversation-central.ts`, `conversation-resources.ts`, `conversation-effect-protocol.ts`, `apps/web/src/automations/node-editors/DomainCommandFields.tsx`, `packages/contracts/src/automation-node-definitions.ts`; tests espelhados de contratos, central e editor.

**Interfaces:** novas variantes `service_desk_intake` (códigos, referência da política e variáveis de coleta) e `service_desk_status` (episódio já obtido). DomainCommandArguments/Result viram união discriminada, preservando variantes CRM. Resultado IntakeDemand com estado e protocolo confirmado; sem URLs/tokens ou dado privado. Capacidades anunciam quais comandos suportados por caixa/configuração, não “tudo” ao existir o endpoint. Autorização Service Desk distinta de CRM. Sem rede GLPI dentro de JrcFlowEffects::Apply.

- [ ] RED: contratos rejeitam campos/versões arbitrários; receipt de outro episódio/caixa/ator é rejeitado; backend antigo não anuncia comandos; cliente CRM sem Service Desk mantém comandos anteriores; editor não exige ownerId CRM para intake.
- [ ] Rodar `npm test -- packages/contracts apps/api/src/modules/automations/conversation-central.test.ts apps/web/src/automations/node-editors/DomainCommandFields.test.tsx` e teste Ruby de protocolo.
- [ ] Implementar união, renderer de variáveis tipadas, capacidades, validação de binding/controle e recibos. Labels explicam cadastro/consulta de demanda, sem anunciar confirmação remota para fila local.
- [ ] GREEN, `npm run typecheck`, `npm test`, `git diff --check`; commit em ambos os repos, sem quebrar os três comandos CRM.

### Task 5: Pendências de informação, conclusão e satisfação

**Files:** Create `app/services/jrc_service_desk/intake/pending_information.rb`, `notification.rb`, `app/jobs/jrc_service_desk/intake_pending_information_job.rb`; Modify listener de entrada/controle conforme padrão encontrado, fora do fluxo de notificação remoto; Test `test/jrc_service_desk/intake_lifecycle_integration.rb`.

**Interfaces:** `PendingInformation.start(demand:, delivered_receipt:)` fixa deadline=delivered_at+48h e geração. `cancel(demand:, event:)` invalida geração. `expire(demand_id:, generation:)` revalida mensagem, estado, revisão e capacidade antes de comando remoto. `Notification.eligible?(demand:, channel:)` permite uma satisfação por conclusão humana confirmada e nunca por FAQ/sem retorno; produção desabilitada no teste.

- [ ] RED: `test_no_delivery_no_clock`, `test_response_cancels_generation`, `test_newest_inbound_beats_stale_job`, `test_takeover_invalidates_pending_bot_action`, `test_missing_glpi_right_does_not_close_local_only`, `test_no_survey_for_no_response`, `test_duplicate_completion_has_single_notification`, `test_outside_channel_capability_has_no_fake_delivery`.
- [ ] Rodar `bundle exec ruby test/jrc_service_desk/intake_lifecycle_integration.rb` com relógio virtual.
- [ ] Implementar locks/geração e transições origem+resultado de negócio separados. Controle de envio único; avisos/satisfação em testes capturados em sink local; nenhum WhatsApp/e-mail externo para fixture.
- [ ] GREEN com corrida de dois workers e entrada; commit `feat(service-desk): control pending intake deadlines and closure`.

### Task 6: Configuração e visibilidade no JRC; geração da URA

**Files JRC:** Create `app/javascript/dashboard/routes/dashboard/jrcServiceDesk/components/IntakeConfiguration.vue` (ajustar diretório ao componente real ao iniciar); Modify tela administrativa GLPI existente e API correspondente para importação/prévia/ativação; Test componente e requests.

**Files locais:** `.private/build_branef_documental_flow.py`, `.private/verify_branef_documental_flow.mjs`, artefatos output citados. Conteúdo do cliente não é commit do Broker.

**Interfaces:** editor configura caixa/modo/catálogo/mapeamentos, mostra bloqueios de entidades/grupos/requester/SLA e matriz de 11 pessoas como prévia sem convites. Demanda no Atendimento conserva metadados e referência GLPI existente. Compilador cria graph nativo validado; os comandos remotos são substituídos por sink sintético nas simulações e desabilitados na versão Welton real.

- [ ] RED: editor mostra prontidão falsa sem calendário/mapeamento; prévia não concede acesso; classificar não assume conversa; matriz de caminhos exige quatro sistemas e 65 submotivos, FAQ condicional Maringá, retorno/correção/handoff e falha de registro sem protocolo falso.
- [ ] Rodar Vitest focado e verificador local do motor (sem rede), confirmar ausência dos novos caminhos inicialmente.
- [ ] Implementar UI com padrões Vue/Tailwind/i18n existentes; importar catálogo privado autenticado. Gerar árvore documental e respostas rastreáveis, preservando links e ramos legados compatíveis, sem inventar conteúdos faltantes. Antes de handoff exibir dados/referência e status de registro.
- [ ] GREEN; auditoria fontes→graph, sem nós órfãos/segredos, nenhum caminho que acione GLPI real em homologação. Commit somente código/UI/testes.

### Task 7: Homologação completa e revisão independente

**Files:** CI/laboratório existentes e nova aplicação sintética `test/glpi_lab/intake_application.rb`; relatório/manifesto privados de cobertura.

- [ ] Rodar regressões de GLPI/fonte nativa, protocolo/CRM/Broker, 48h e concorrência; GLPI isolado com dados sintéticos e sink de notificações. Medir cobertura de ramos, não só total de testes.
- [ ] Conferir lint, migrations timestamps, production builds, ausência de credenciais/clientes reais no Git e `git diff --check` em ambas branches. Registrar RED/GREEN por tarefa e limites reais de catálogo/API.
- [ ] Revisão independente completa com spec/plano/ledger, por skill requesting-code-review. Corrigir Critical/Important em uma passada com regressões RED/GREEN e suíte verde; nenhuma re-revisão redundante.
- [ ] Registrar pendências de direitos/mapeamento/calendário como pendências de entrega, nunca como sucesso integral.

### Task 8: Publicação e implantação restritas à homologação Branef

- [ ] Publicar branches e imagens por SHA/digest após gates, conforme escopo aprovado; nenhuma alteração em branch compartilhada/default sem necessidade.
- [ ] Conferir instalação e origens de destino, aplicar backend compatível JRC e Broker opt-in, preservando outros serviços/canais, dados e credenciais. Identificar efeito do deploy Broker compartilhado antes da ação; sem mudar configuração de outros clientes.
- [ ] Configurar catálogo/revisão e Flow na caixa Welton de teste, GLPI real disabled. Prévia deve mostrar as dependências de produção e não tentar preenchê-las com valores inventados.
- [ ] Verificar containers/saúde/preparação, interface autenticada, todos os menus no simulador e rotas físicas controladas com o usuário; sem mensagens para contatos alheios ao teste. Identificar cada rota comprovada e o que só passou no laboratório.
- [ ] Atualizar relatório com funcionamento, configurações, rollback, protocolo, cobertura e passos restantes para número oficial/GLPI real. Declarar concluída a homologação do que foi comprovado; não declarar produção completa com dependências pendentes.

## Auto-revisão do plano

Cobertura: catálogo e fontes (1), persistência/isolamento (2), GLPI e SLA (3), transporte/editor (4), 48h/satisfação (5), usuários/prévia/UI/graph (6), provas/revisão (7), runtime/rollback/relatório (8). Os cinco Review Focus têm casos nomeados nos proprietários. Resultado domain não altera o formato CRM; entrega assíncrona evita rede dentro do lock de conversa. IDs e calendários reais são dependências explicitadas, sem promessa de inferência dos documentos.
