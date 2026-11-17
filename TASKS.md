<!-- jrc-operational-init:v1 -->
# Backlog operacional — JRC Conversas Branef — GLPI

## Em progresso (WIP)

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
