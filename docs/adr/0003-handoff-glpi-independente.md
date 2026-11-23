# 0003 - Transferência humana independente da entrega GLPI

- Estado: Aceita
- Data: 17/11/2026
- Escopo: JRC Branef e protocolo compatível do Broker

## Contexto

Uma indisponibilidade GLPI não deve impedir o cliente de chegar à equipe humana. A execução anterior podia colocar IO antes da transferência ou perder a autorização de origem ao mudar o controle da conversa.

## Decisão

O comando autenticado service_desk_handoff valida destino e controle e registra a coleta local, a abertura/atribuição da conversa e o recibo imutável na mesma transação. O job GLPI somente inicia após o commit. Não chamar GLPI na transferência. Coleta inválida ou configuração de intake indisponível gera nota privada e não impede o atendimento humano autorizado.

O protocolo intake 2 anuncia essa capacidade independentemente da existência de uma configuração de abertura habilitada. A autorização do operador, conta, caixa, destino e origem continua obrigatória. O job que sobrevive à transferência exige recibo imutável correspondente a conta, conversa, ator, operação, episódio, configuração e demanda. Revogação da credencial ou da configuração continua bloqueando entrega.

O Broker persiste a coleta renderizada no ledger nativo e usa o mesmo comando JRC. Captura inválida ou maior que os limites segue para revisão manual sem truncar o histórico. Resposta perdida conserva UNKNOWN e conciliação somente GET, sem repetir POST. Confirmar a atribuição não prova criação de chamado GLPI.

## Consequências e verificação

Compatibilidade preservada para handoff sem intake e protocolo anterior. Não há migration nova. Os prazos atuais, unidades nativas e calendário do ADR0002 permanecem. O usuário técnico é o existente jrc.conversas ID100; Integração JRC é o perfil, não novo usuário.

Testes locais: 12 cenários/64 assertivas de handoff Rails; 170 testes direcionados Broker e typecheck; 3248 turnos de simulação da árvore, incluindo 82 FAQs e 171 coletas. A rodada agregada Rails foi interrompida após timeout de concorrência em lifecycle e não representa aprovação integral. CI, imagem e implantação precisam de provas próprias. Escritas no GLPI real continuam aguardando liberação e homologação autorizada.
## Correção dos gates de publicação - 17/11/2026

As validações de mapeamento e readiness foram divididas sem retirar verificações de escopo, SLA, grupo ou solicitante. Os quatro comandos de contratos passaram (7/16,13/26,23/46,12/24; há casos herdados entre comandos, não somar como únicos). O gate completo de lint66arquivos passou sem ocorrências. A fixture de modelo não suportado do laboratório foi atualizada para locations_id: requesttypes_id passou a ser suportado para a origem WhatsApp. A recusa de campo obrigatório não suportado e zero escritas continuam exigidas; o novo laboratório porSHA ainda deve confirmar esse cenário.
