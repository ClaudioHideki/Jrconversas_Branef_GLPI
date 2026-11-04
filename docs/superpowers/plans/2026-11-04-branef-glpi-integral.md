# Branef GLPI integral Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Operar os registros GLPI de todas as 21 entidades da Branef pelas telas do Service Desk, com auditoria do operador JRC e confirmacao de cada comando na origem.

**Architecture:** GLPI permanece a origem oficial; contratos de leitura/comando e projecoes locais alimentam as telas. A selecao de origem e por conexao/Account, preservando a origem nativa das demais contas. Credencial tecnica e direitos JRC/GLPI sao verificados no backend.

**Tech Stack:** Rails 7.1, Ruby 3.4.4, PostgreSQL 16/pgvector, Redis/Sidekiq, Vue 3, Vitest, API REST V1 GLPI 10.0.18, laboratorio Docker isolado.

**Spec:** docs/superpowers/specs/2026-11-04-branef-glpi-integral-design.md, aprovada em 04/11/2026 junto com testes, publicacao e implantacao somente na Branef.

## Global Constraints

- Branef Account 3; raiz 0, SUPORTE 1/7/8/9/10/11/12/13/14/15/16/17/22/23/24/25 e SEDE 21/18/19/20. IDs sao configuracao, nunca condicoes fixas no produto.
- Usuario tecnico no GLPI; registrar AccountUser e usuario JRC iniciadores. Nenhuma simulacao de autoria pessoal GLPI.
- Nao escrever em chamados reais do cliente sem ambiente/registros de teste identificados e autorizados. Laboratorio usa somente sinteticos.
- Tokens cifrados no backend, sem credenciais em codigo, navegador, logs ou evidencias.
- Preservar conta 3, unidades e chamados locais existentes. Nao recriar a conta 2, nao regenerar chaves, nao alterar SMTP/S3/NICO para esta ampliacao.
- Dados bloqueados/antigos/parciais devem ficar identificados; 403 nao e vazio, 404 nao comprova exclusao.
- Novas unidades raiz/SEDE inicialmente administrativas, sem concessoes automaticas a agentes.
- Sem corte oculto de historico em 100 ou export em 10 mil. Paginar e reconciliar cobertura.
- Conferir Enterprise antes de alterar interfaces compartilhadas. Usar componentes existentes e traducoes em locale/en; manter o carregamento de traducoes GLPI ja existente.
- Usar a branch codex/branef-glpi-integral-20261104, baseada na revisao implantada 86f64ca467fc18930105c9157bb9e3f933aa2f78.

## Review Focus

- ID de entidade zero e nome ausente nao podem ampliar nem eliminar escopo: tarefa 2 exercita 0 e entidades sem rotulo, sem fallback de unidade.
- Uma revogacao depois de preparar comando/export deve impedir execucao/download: tarefas 4 e 6 exercitam revogacao e troca de conexao.
- Colecoes globais e anexos nao podem expor registros de outra conta, unidade ou chamado: tarefas 3 e 5 exercitam relacao remota incorreta e conteudo privado.
- Timeout depois de gravar nao pode provocar segunda gravacao: tarefa 4 exercita POST ambiguo, replay e reconciliacao.
- Mudanca de Account/usuario durante uma resposta pendente nao pode popular a nova tela: tarefa 7 exercita geracao de sessao e cancelamento.

## Execucao e registro

Execucao inline ja autorizada, com uma revisao independente da branch ao final. Registrar cada tarefa e decisao no ledger .superpowers/sdd/2026-11-04-branef-glpi-integral/progress.md dentro do worktree. O checkout de produto fica em .private/branef-glpi-integral; nao copiar branef.env nem arquivos privados para ele. A ferramenta nativa de worktree recusou o repositorio aninhado; o worktree Git foi criado no diretorio privado ignorado. O plano e a especificacao sao copiados para o worktree e versionados com a implementacao.

### Task 1: Cliente paginado e limites da API

**Files:** modificar app/services/jrc_service_desk/glpi/client.rb; criar app/services/jrc_service_desk/glpi/collection.rb; criar test/jrc_service_desk/glpi_transport_test.rb.

**Interfaces:** Client#get preserva retorno atual. Client#collection(path, parameters = {}, batch_size: 200) retorna Enumerator de Hash; Client#create_item(type, input), #update_item(type, id, input), #delete_item(type, id, purge: false) usam somente tipos permitidos pelo executor. Client#last_response expose apenas status/Content-Range/Accept-Range, nunca headers de autenticacao.

- [ ] Escrever testes: 205 eventos em paginas 200+5 produzem 205 IDs; erro 403 na segunda pagina interrompe; pagina repetida/sem progresso gera source_changed; resposta vazia sem data so vale com totalcount zero; paths relativos de tipos conhecidos nao permitem URL arbitraria.
- [ ] Executar `bundle exec ruby test/jrc_service_desk/glpi_transport_test.rb`; observar RED por comportamento ausente.
- [ ] Implementar paginacao com metadados reais e limites anunciados, preservando contrato GET e limpeza de sessao. Nao introduzir retry de escrita.
- [ ] Executar o arquivo e os 32 casos existentes de glpi_integration.rb no banco descartavel branef_glpi_test; esperar todos PASS.
- [ ] Commit `feat(glpi): add complete collections and typed transport`.

### Task 2: Origem por Account e indice autorizado

**Files:** criar db/migrate/20261104130000_expand_glpi_service_desk.rb; modelos glpi_ticket_snapshot.rb e glpi_sync_run.rb; servicos glpi/primary_source.rb e glpi/sync_tickets.rb; job jrc_service_desk/glpi_sync_job.rb; modificar glpi_connection.rb, ui_context_service.rb e helpers/contracts.js; criar test/jrc_service_desk/glpi_projection_integration.rb.

**Interfaces:** GlpiConnection#primary_source?; PrimarySource.for(context) devolve native/glpi da conta autenticada. SyncTickets#call(connection:, actor:) registra cobertura por entidade e projeta IDs/campos permitidos. Snapshot chave unica connection+remote_id, entity_id/unit_id derivados de consulta explicita ou detalhe verificado, nunca do rotulo. UiContext inclui data_source com default native.

- [ ] Testar conta nativa preservada, root 0 indexada, nome ausente sem unidade inventada, duplicata detectada, falha parcial visivel, outra conta negada e mudanca de conexao invalidando cache.
- [ ] Rodar testes e observar RED; criar schema aditivo com referencias de Account e indices compostos.
- [ ] Implementar sincronizacao por entidades autorizadas e coletas paginadas, progressos/falhas e horario; nao afirmar snapshot atomico da origem.
- [ ] Rodar integracao/projecao e contratos frontend; esperar isolamento e defaults verdes.
- [ ] Commit `feat(glpi): add account source and scoped ticket projections`.

### Task 3: Recursos, capacidades e leitura de todo o contexto

**Files:** criar glpi/operation_catalogue.rb, glpi/resource_query.rb, glpi/capabilities.rb e glpi/detail.rb; modificar glpi_controller.rb e config/routes.rb; criar test/jrc_service_desk/glpi_resources_integration.rb.

**Interfaces:** OperationCatalogue.fetch(operation) devolve tipo, verbo, campos, capacidade JRC e relacao pai. ResourceQuery#call(access:, client:, kind:, filters:) devolve items/meta/coverage; Detail#call(access:, client:, ticket_id:) inclui relacoes paginadas autorizadas. Capabilities#call(access:, client:) distingue supported, permitted e source_checked em cada operacao. Endpoints GLPI /capabilities, /resources/:kind, /tickets/:id/relations/:kind.

- [ ] Testar User/Group/category/document negados como 403; relacao de outro chamado negada; notas privadas ocultas de agentes; problema/mudanca com entidade nao mapeada negados; historico com 205 entradas completo.
- [ ] Observar RED; implementar allowlist de recursos/campos e verificacao de entidade/parentesco antes de entregar dados ou aceitar seletor.
- [ ] Implementar atores, categorias/modelos, tarefas, acompanhamentos, solucoes, validacoes, problemas, mudancas, conhecimento, ativos vinculados, SLA e satisfacao conforme a API instalada.
- [ ] Rodar recursos, autorizacao e regressao GLPI; esperar nenhum vazamento e indisponibilidade explicita.
- [ ] Commit `feat(glpi): expose scoped resources and operation capabilities`.

### Task 4: Comandos duraveis e todos os verbos operacionais

**Files:** criar glpi/execute.rb, glpi/command_input.rb e glpi/reconcile.rb; modificar glpi_command.rb, glpi_controller.rb, glpi_policy.rb e routes; criar test/jrc_service_desk/glpi_commands_integration.rb.

**Interfaces:** Execute#call(access:, operation:, target_id:, entity_id:, attributes:, idempotency_key:, expected_version: nil, reason: nil) devolve receipt. O manifesto define explicitamente pai, alvo e campos de cada operacao. Receipt inclui operacao/tipo/alvo/estado/resultado, sem segredos. POST /glpi/operations executa somente operacao cadastrada. Reconcile#call verifica resultado/correlacao remota; nao repete POST indeterminado.

- [ ] Testar editar/atribuir/transferir/pendencia/solucionar/fechar/reabrir chamado; criar/editar/retirar acompanhamento; CRUD de tarefa; pedir/decidir validacao; CRUD de problema/mudanca/conhecimento e vinculos autorizados.
- [ ] Testar chave repetida sem segundo envio, payload alterado em mesma chave como conflito, timeout depois de POST indeterminado, revogacao/configuracao alterada antes de enviar, alvo de outra entidade negado e versao divergente recusada.
- [ ] Observar RED; ampliar recibos e implementar validacao de campos, capacidades locais e da origem, intencao persistida antes da rede e serializacao local por objeto.
- [ ] Conferir campos antes/depois da escrita; registrar usuario tecnico GLPI e operador JRC. Validacao destinada a outra identidade deve continuar sendo recusada pela origem.
- [ ] Rodar suite de comandos, recursos e 32 casos anteriores; esperar PASS sem gravacao no GLPI cliente.
- [ ] Commit `feat(glpi): execute audited idempotent service desk operations`.

### Task 5: Documentos e conteudo do atendimento

**Files:** criar glpi/documents.rb e test/jrc_service_desk/glpi_documents_integration.rb; ampliar cliente/controlador/rotas para upload multipart, download e associacao; componente GlpiDocuments.vue.

**Interfaces:** Documents#download(access:, client:, ticket_id:, document_id:) retorna bytes/filename/content_type apos verificar Document_Item. #upload registra documento e associacao em etapas do recibo. Limites operacionais explicitos de 20 MiB upload e 50 MiB download; origem pode recusar limites menores. Nenhuma URL de descricao recebe tokens.

- [ ] Testar documento de outro chamado/conta negado, upload correto e associacao uma vez, arquivo compartilhado sem exclusao global ao retirar vinculo, timeout entre criar e associar sem duplicar documento e limite excedido claro.
- [ ] Observar RED; implementar streaming/buffer limitado, nome sanitizado e download autenticado via backend; nao publicar URL S3/GLPI credenciada.
- [ ] Rodar testes de documentos, comandos e privacidade; esperar PASS.
- [ ] Commit `feat(glpi): integrate authorized documents and attachments`.

### Task 6: Paineis e exportacao completa

**Files:** criar glpi/overview.rb, glpi/export.rb, glpi_export.rb e glpi_export_job.rb; modificar report.rb, ticket_query.rb, controlador/rotas; criar test/jrc_service_desk/glpi_exports_integration.rb.

**Interfaces:** Overview#call(access:, filters:) retorna metricas por mesmo escopo da lista, cobertura e generated_at. Export#prepare(access:, filters:) retorna job/receipt; ExportJob produz CSV completo no storage com expiracao de artefato em 24h. Download revalida usuario/conta/unidades/conexao e escopo da origem; 403 nao fornece arquivo previamente gerado.

- [ ] Testar 10.205 registros completos, sem teto silencioso; CSV vazio apenas cabecalho; formula injection neutralizada; geracao parcial nao aparece como pronta; revogacao depois de preparar impede baixar; falha de quota nao vira export truncado.
- [ ] Observar RED; implementar leitura por lotes com progresso/erros e download autorizado, sem carregar todo o historico em uma requisicao interativa.
- [ ] Rodar testes de export/overview e regressao; esperar contagens coerentes e cobertura explicita.
- [ ] Commit `feat(glpi): add consistent dashboards and asynchronous exports`.

### Task 7: Integracao nas telas nativas

**Files:** modificar ServiceDeskLayout.vue e contratos de contexto; criar glpi/GlpiServiceDesk.vue, GlpiOverview.vue, GlpiResourceBoard.vue, GlpiOperationForm.vue e helpers/glpiScreens.js; ampliar GlpiWorkspace.vue, useGlpi.js, serviceDeskGlpi.js e traducoes existentes em locale/en; criar glpi/GlpiServiceDesk.spec.js e glpi/glpiScreens.spec.js.

**Interfaces:** GlpiServiceDesk({ screen, ticketId }) seleciona tela remota conforme rota/contexto; recebe data_source do backend, nunca de localStorage. Operacoes do formulario usam descriptors do manifesto com labels traduzidas, sem campos JSON brutos. A origem nativa conserva RouterView atual. Configuracao/estrutura JRC conserva rotas locais explicitamente identificadas.

- [ ] Testar conta native mostrando tela nativa; conta GLPI mostrando overview/lista/minha fila/tarefas/aprovacoes/problemas/mudancas/conhecimento/anexos/SLA/relatorios com a mesma origem; erro 403 visivel; acao indisponivel explicada; resposta tardia de outra conta descartada.
- [ ] Observar RED em Vitest; implementar selecao por fonte e telas com componentes existentes, formularios legiveis, progresso e recibos.
- [ ] Conectar edicao e as acoes obrigatorias do manifesto; nao encaminhar um ID GLPI ao controlador de chamado nativo. Controles sem equivalente ficam identificados como nao aplicaveis.
- [ ] Rodar Vitest ServiceDesk, sidebar e contratos; esperar a regressao existente verde.
- [ ] Commit `feat(glpi): use GLPI across service desk workspaces`.

### Task 8: Automacoes e referencias locais

**Files:** criar glpi/reference.rb e glpi/automation_command.rb; integrar puntos de entrada de conversas/NICO/case-links e automacoes identificados na pesquisa; testar em test/jrc_service_desk/glpi_automation_integration.rb.

**Interfaces:** Reference contem Account/connection/itemtype/remote_id/entity_id; AutomationCommand chama Execute com operador e unidade autorizados, sem finalizar apenas snapshot. Conversas ligam a referencia remota; notificacoes GLPI nao sao duplicadas por automacao JRC.

- [ ] Testar referencia com mesmo ID nativo/remoto distinta, execucao automatica negada depois de revogacao, mesma chave sem duplicar e origem local preservada.
- [ ] Observar RED; implementar os pontos de integracao sem enviar automaticamente toda a base a provedor IA.
- [ ] Rodar automacao, comandos e regressao dos modulos relacionados; esperar PASS.
- [ ] Commit `feat(glpi): route linked workflows through authorized commands`.

### Task 9: Laboratorio GLPI 10.0.18 e homologacao

**Files:** criar test/glpi_lab/compose.yaml, Dockerfile, bootstrap.php e run.rb; criar workflow CI da branch; atualizar gates da publicacao.

**Interfaces:** laboratorio com projeto Docker exclusivo, MariaDB e GLPI 10.0.18/PHP suportado, apenas sinteticos. O transporte de teste usa host allowlisted .example.invalid e adapta a rede privada no helper de testes, sem excecao SSRF em producao. Bootstrap instala entidades/perfis/usuarios sintéticos e retorna so IDs; segredos do laboratorio ficam em arquivo ignorado/variaveis locais.

- [ ] Instalar laboratorio e comprovar versao; executar os fluxos de Task 4/5 contra a API real do laboratorio.
- [ ] Exercitar perfil tecnico limitado, root 0, unidades, notas privadas, validacao e documentacao da autoria tecnica. Falhas devem testar resultados reais, nao apenas mocks.
- [ ] Executar suites Ruby, Vitest afetadas, lint e build; corrigir falhas antes de publicar.
- [ ] Registrar separadamente mock/CI, laboratorio real e leitura do GLPI cliente. Nao executar escrita em cliente sem registro/ambiente autorizado.
- [ ] Commit `test(glpi): validate complete integration against GLPI 10 laboratory`.

### Task 10: Revisao, imagem e implantacao Branef

**Files:** especificacao/plano/ledger, deploy/branef docs, evidencias sem segredos, workflow e configuracao real privada fora do repositorio.

- [ ] Fazer revisao independente da branch e corrigir problemas importantes com teste reproduzindo a falha; registrar limites honestamente.
- [ ] Publicar a branch e gerar imagem linux/amd64 por SHA; verificar CI, OCI revision, .git_sha e digest antes de implantar.
- [ ] Conferir estado real do Dokploy/Account 3; inventariar membros, registros locais e mapeamentos. Aplicar root/SEDE em unidades administrativas com IDs retornados, conservar SUPORTE; ativar fonte GLPI apenas nessa conta.
- [ ] Alterar somente a imagem/configuracao necessaria e rodar migrations aditivas; conferir prepare=0, Rails/Sidekiq, banco/Redis/NICO, HTTPS e revisao em execucao.
- [ ] Rodar leitura pelo Rails, reconciliar cobertura/contagens/IDs/entidades, percorrer paineis e comprovar indisponibilidades reais. Nao declarar completa enquanto capacidades obrigatorias dependam de permissao ou homologacao.
- [ ] Atualizar relatorio final e matriz com o que foi comprovado e o que depende do administrador GLPI; preservar credenciais/volumes e nao gerar novos backups manuais.

## Cobertura e revisao do plano

As tarefas 1-6 entregam os contratos consumidos por 7-8. A tarefa 9 comprova os verbos do manifesto; 10 depende de todos os gates. As cinco condicoes de Review Focus estao atribuidas a testes explicitos. Origem por conta, atores, unidades, documentos, concorrencia e diferencas da API V1 seguem a especificacao aprovada. Nenhuma dependência externa bloqueada permite simular conclusao.
