<!-- jrc-operational-init:v1 -->
# Roadmap operacional — JRC Conversas Branef — GLPI

Referência inicial: INIT solicitado pelo usuário em 2026-11-13. É uma trilha documental Brownfield, não uma declaração de conclusão do produto.

## Fase 1: Fundação e alinhamento de contexto

- [x] Identificar o projeto e preservar as regras existentes em AGENTS.md.
- [x] Organizar o domínio em docs/domain/ e a arquitetura em docs/architecture/.
- [x] Configurar o pipeline documental de tarefas em TASKS.md e o registro ADR.
- [ ] Revisar os mapas iniciais com os responsáveis do projeto e manter as fontes atualizadas.

## Fase 2: Operação e desenvolvimento ativo

- [ ] Preservar o trabalho visual em andamento e as regras GLPI específicas.
- [ ] Validar classificação, roteamento e entrega antes de ativar integrações ou números.
- [ ] Registrar critério de aceite, teste pertinente e evidência de cada alteração funcional autorizada.

## Fase 3: Estabilização e manutenção

- [ ] Documentar casos de borda comprovados e dependências operacionais.
- [ ] Otimizar rotinas repetitivas somente após medir a necessidade.
- [ ] Revisar proveniência, isolamento e versões a cada candidata de release.

Veja [TASKS.md](TASKS.md). Roadmaps e planos anteriores continuam válidos no seu escopo.

Incremento 18/11: retorno documental aceito pelo usuário; prioridade explícita em rotas BUG conforme ADR 0004. CI, imagem, implantação, configuração e teste real permanecem etapas separadas no GLPI-18-RETORNO.

## Incremento de 17/11/2026 — retorno GLPI

O contrato local foi ajustado para os prazos nativos atuais, atributos na criação e políticas aprováveis de solicitante, preservando rotas anteriores. Ver [ADR 0002](docs/adr/0002-intake-prazos-nativos-glpi.md). A ativação automática permanece condicionada à coordenação com a transferência humana, às liberações GLPI e à homologação. O código e os candidatos locais não comprovam imagem publicada ou execução em produção.

Transferência independente preparada em código e testes dirigidos: [ADR0003](docs/adr/0003-handoff-glpi-independente.md). O GLPI não é consultado dentro da transação de encaminhamento humano. Ainda requer evidência de release e ativação.
