# Histórico GLPI na análise de sentimento

Autorizado em 23/11/2026: analisar outubro e novembro de 2026, sem enviar mensagens. Novembro é parcial até a coleta. Abertura automática e outros clientes permanecem preservados.

O adaptador exclusivo Branef usa as permissões de chamado, unidade, entidade e dashboard existentes. Sessões de leitura, sem criação/alteração GLPI. Notas privadas são excluídas inclusive para administradores; acompanhamentos sem visibilidade pública comprovada não entram na análise. A origem, IDs qualificados, período, fuso configurado na conexão, versão e digest da projeção acompanham o resultado. O usuário técnico da sessão tem autoria desconhecida; associação como técnico não é prova de atuação humana.

GET /api/v1/accounts/:account_id/jrc_service_desk/glpi/sentiment/candidates?from=2026-10-01&to=2026-12-01 enumera candidatos autorizados, incluindo chamados anteriores com alterações no período. A sessão de leitura precisa cobrir todas as entidades mapeadas do operador, ou a enumeração falha explicitamente com source_scope_incomplete. POST /api/v1/accounts/:account_id/jrc_service_desk/glpi/tickets/:remote_id/sentiment recebe from/to e analisa somente textos públicos cuja data está no intervalo semiaberto. Exige os mesmos cabeçalhos de binding e autenticação do Service Desk.

São analisados até 100 registros públicos por chamado, com 1000 caracteres por registro; omissões e truncamentos ficam explícitos. Sem texto público, nenhum consumo de IA é iniciado. Resultado inferido não representa resposta a pesquisa de satisfação. O consumo é contabilizado pelo recibo real do provedor. A projeção não envia anexos, áudios, notas privadas nem credenciais.

Contrato genérico de origem implementado no núcleo LAB2; leitura GLPI somente na Branef. Sem migration. CI, imagem, implantação e análise real permanecem etapas de evidência distintas.

## Coleta em ambiente ativo

A primeira leitura real abortou com source_changed durante a paginação da coleção completa de tickets. A enumeração agora usa campos efetivamente identificados por listSearchOptions/Ticket, filtros de entidade/data e uma janela superior de IDs reais capturada da própria API. IDs são enumerados antes das leituras individuais autorizadas, com páginas limitadas a1000 identificadores. A proteção global de paginação permanece intacta; contagens instáveis continuam abortando. O corte parcial é convertido ao fuso configurado na conexão antes da consulta.

A pré-validação identificou que, no GLPI10, comparações numéricas usam searchtype=contains com o operador no valor (por exemplo <= seguido do ID real capturado). Um searchtype=lessthan com valor numérico puro vira igualdade nessa versão. A janela agora precisa conter o ID máximo capturado, ou aborta com source_changed em vez de informar um histórico vazio incorreto. Referência: https://github.com/glpi-project/glpi/blob/10.0/bugfixes/src/Search.php
