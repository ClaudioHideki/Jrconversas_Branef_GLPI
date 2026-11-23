# 0002 — Intake com prazos nativos e atributos de criação

- Estado: Aceita
- Data: 17/11/2026
- Escopo: JRC Conversas Branef / GLPI

## Contexto

O retorno do cliente compara os prazos antigos da árvore com os efetivamente existentes no GLPI. O usuário declarou os anexos como referência consolidada e escolheu manter os prazos atuais do GLPI e ajustar a árvore. As rotas anteriores aplicavam grupo e SLA em etapas posteriores à criação.

## Decisão

As novas rotas podem enviar grupo, origem WhatsApp e SLAs de primeiro atendimento e solução no POST inicial. O contrato anterior com um SLA e etapas separadas continua aceito. Não converter dias em horas. Melhoria pode ter SLA de primeiro atendimento sem inventar prazo de solução.

A herança de SLA, SLM, calendário e grupo exige recursividade e escopo contextual da entidade do chamado. Isso não concede acesso operacional à entidade ancestral. Usar o expediente documentado: segunda a quinta 08–18h e sexta 08–17h. Maringá conserva os SLAs atualmente herdados de SIVISA+.

O mapeamento por contato continua como padrão. A busca exata por e-mail e a alternativa anônima somente ficam disponíveis com política explicitamente aprovada; não criar usuários automaticamente. E-mail informado é pista de encaminhamento, não comprovação de identidade.

## Consequências

Validar duração, unidade, calendário, finalidade TTO/TTR e permissões antes do envio. Respeitar campos obrigatórios, ocultos e predefinidos do template. A confirmação depende da leitura do chamado e seus vínculos depois do POST. Resultado indeterminado não autoriza repetir o envio.

A validação do SLA ocorre na preparação do envio; consultar a entidade de uma coleta ainda incompleta não exige configurar previamente o SLA. As verificações de conta, unidade, credencial e controle da conversa permanecem vigentes.

O candidato da URA com coleta e transferência sem IO permanece separado do candidato de abertura automática. Este último não pode ser ativado até validar a recuperação de UNKNOWN e a coordenação com a transferência humana. Preparação local, publicação e homologação são estados distintos.

## Evidências

- `test/jrc_service_desk/intake_route_contract_test.rb`
- `test/jrc_service_desk/intake_source_contract_test.rb`
- `test/jrc_service_desk/intake_readiness_contract_test.rb`
- `test/jrc_service_desk/intake_creation_attributes_integration.rb`
- `test/jrc_service_desk/intake_submission_integration.rb`

Os anexos, o catálogo candidato e os logs ficam no projeto de coordenação JRCBranef, em `output/ajustes-jrc-glpi-20261117/`. Não são configuração ativa de produção.
