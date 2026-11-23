# 0004 — Prioridade explícita para BUG no intake Branef

Estado: Aceita. Data: 18/11/2026.

## Contexto

O retorno documental de 17/11 e sua planilha foram aceitos pelo usuário como referência para configuração e testes. O GLPI exige prioridade explícita 2/3/4/6 para BUG baixo/médio/alto/crítico, mantendo impacto e urgência em 3. A matriz anterior não produz prioridade crítica nessas condições.

## Decisão

Complementar o ADR 0002 permitindo `priority` inteira de 1 a 6 somente em rotas BUG com severidade conhecida e atributos definidos na criação. O valor provém da configuração aprovada no servidor, nunca da entrada do visitante. Configurações anteriores continuam usando seu contrato original. Não alterar regras de negócio globais do GLPI ou atendimento de outros clientes.

## Consequências e evidências

O teste de contrato cobre as quatro prioridades, os eixos 3/3, a compatibilidade anterior e a rejeição de valores inválidos ou rotas não BUG. CI, imagem, implantação e teste operacional precisam de evidência própria. As regras GLPI descritas no retorno ainda podem substituir SLA, grupo ou status; registrar o resultado efetivo no teste, sem presumir correção dessas regras. Não executar backup, dump ou restore.

Na verificação do runtime em 18/11, as 555 rotas passaram pela qualificação local, mas a prontidão falhou com ArgumentError em ReadOnlySource#get: TicketForm consulta getMyEntities com parâmetros e o adaptador aceitava somente o caminho. Encaminhar os parâmetros e incluí-los na chave de cache, preservando escopos distintos e a chamada sem parâmetros. Regressão cobre consulta recursiva/não recursiva e compatibilidade anterior. O bloqueio independente HTTP 403 em RequestType/8 continua dependendo do perfil GLPI.
