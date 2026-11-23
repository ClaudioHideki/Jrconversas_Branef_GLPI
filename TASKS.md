<!-- jrc-operational-init:v1 -->
# Backlog operacional — JRC Conversas Branef — GLPI

## Em progresso (WIP)

- [ ] **GLPI-18-RETORNO:** Aplicar perfil 14/categoria 190 e rotas aprovadas, prioridade BUG explícita, validar CI do SHA final, publicar imagem e configuração, testar JRC Conversas/URA/GLPI e registrar regras que substituem os atributos enviados. Perfil 14 e categoria 190 confirmados por leitura autenticada em 18/11; ver ADR 0004. Não confundir validação documental com homologação operacional.

Nenhuma execução funcional é iniciada por este bootstrap. As frentes já em andamento permanecem nos planos/checkpoints existentes.

- [ ] **GLPI-17-ATIVACAO:** Concluir a coordenação entre abertura automática e transferência humana, inclusive resultado UNKNOWN. O candidato de coleta sem IO preserva a transferência; o candidato de abertura continua bloqueado. Publicação, configuração final e homologação real ainda são etapas distintas.
- [ ] **GLPI-17-EXTERNO:** Aguardar perfil exclusivo no usuário técnico existente, permissões, categoria/grupo ausentes, política de solicitantes e ambiente autorizado de homologação. Não solicitar a substituição dos prazos atuais do GLPI pelos antigos da árvore.

## A fazer (To Do)

- [ ] **DOC-01:** Revisar os termos de [glossary.md](docs/domain/glossary.md) com o responsável pelo domínio.
- [ ] **DOC-02:** Conferir [system-overview.md](docs/architecture/system-overview.md) e as versões com o ambiente efetivo quando houver acesso autorizado.
- [ ] **OPS-01:** Preservar o trabalho visual em andamento e as regras GLPI específicas.
- [ ] **OPS-02:** Validar classificação, roteamento e entrega antes de ativar integrações ou números.

## Concluído (Done)

- [x] **BOOTSTRAP-01:** Identidade, stack, natureza Brownfield e fontes locais registradas.
- [x] **BOOTSTRAP-02:** Estrutura INIT, domínio, arquitetura e ADR organizados sem apagar conteúdo anterior.
- [x] **GLPI-17-CONTRATO:** Preparado o contrato de grupo, origem e TTO/TTR na criação, com políticas condicionais de solicitante, herança contextual e compatibilidade anterior. Evidências nos testes direcionados e no ADR 0002; não equivale a implantação.

## Como manter

Uma tarefa deve registrar problema, escopo, critério de aceite, evidência/arquivo e limite. Só mover para Concluído com a prova correspondente; não converter publicação de imagem em aceite operacional.

- [x] **GLPI-17-HANDOFF-CODIGO:** Comando local atômico, recibo imutável e job posterior implementados; 12 cenários/64 assertivas aprovados. Ver ADR0003. CI, publicação, implantação e homologação permanecem separados.

## Consumo NICO — 23/11/2026

- [x] Implementar candidata com controle pelo provedor e teto local opcional; preservar reservas incertas e isolamento. Ver ADR0007.
- [ ] Concluir testes nativos/CI, publicação das imagens e implantação autorizada na Branef. Validação local não comprova ambiente atualizado.

## Groq HTTP 429 — 23/11/2026

- [x] Integrar seletivamente a recuperação de Retry-After do núcleo, mantendo GLPI e a versão implantada 0861e68e.
- [ ] CI da candidata e publicação apenas do runtime; aplicação, URA e abertura automática preservadas.
- [ ] Homologar conhecimento e recuperar resultado da leitura de prontidão iniciada anteriormente antes de disparar outra leitura. Ver docs/adr/20261123-groq-retry-after.md.

- [ ] **GLPI-SENTIMENT-20261123:** Adaptador/API de histórico público por período implementado em candidata; executar CI e homologar outubro/novembro, sem mensagens. Ver ADR20261123-glpi-historical-sentiment.
