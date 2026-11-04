# BRANEF: GLPI integrado ao Service Desk

Data: 04/11/2026, America/Sao_Paulo. Estado: aprovada em 04/11/2026 para implementacao, testes, publicacao e implantacao somente na Branef; execucao iniciada, sem nova implantacao ainda.

Revisao de planejamento concluida: escopo de verbos, identidade tecnica, acesso inicial das novas unidades e laboratorio de testes foram explicitados. O revisor nao identificou outra decisao importante do responsavel antes de elaborar o plano. Permissoes reais e homologacao no cliente continuam dependencias de execucao, nao comprovacoes ja obtidas.

## Objetivo confirmado

O responsavel quer consultar todos os chamados da Branef e operar o GLPI pelas telas do JRC Service Desk, incluindo seus paineis, filas, historicos e acoes. Confirmou expressamente todas as entidades da Branef, inclusive raiz e SEDE. A conta de destino e a BRANEF 3. A ampliacao nao autoriza executar indiscriminadamente alteracoes, exclusoes ou aberturas nos chamados reais: essas sao funcionalidades a implementar e homologar.

## Evidencias e limites da auditoria

O codigo inspecionado corresponde ao SHA 86f64ca467fc18930105c9157bb9e3f933aa2f78, ultima revisao implantada e comprovada em 03/11. Os controladores, servicos de acesso, cliente HTTP, consultas, normalizacao, relatorios, modelo de conexao, permissoes, dashboard e quadros operacionais foram lidos. A revisao em execucao nao foi reconferida em 04/11: o controle do navegador ficou indisponivel antes de abrir o painel. As chamadas abaixo foram feitas diretamente da estacao Windows, com TLS verificado, tokens somente em memoria e encerramento de sessao; nao partem do IP do Rails.

Resultados de 04/11, entre 11:41 e 11:46 de Sao Paulo:

| Consulta | Resultado observado |
|---|---|
| Autenticacao | HTTP 200, perfil Suporte 6 |
| Versao informada pela origem | GLPI 10.0.18 |
| Entidades disponibilizadas | 21, incluindo raiz 0 e SEDE 21 |
| Busca ampla, sem filtro explicito de entidade | 884 visiveis a credencial, HTTP 206; consulta de contagem |
| Busca com o filtro atual das 16 entidades SUPORTE | 2, HTTP 206; consulta de contagem |
| Busca com as 21 entidades explicitamente filtradas | 883 linhas e 883 IDs distintos, total informado 883 |
| Entidade exibida nessa resposta completa | BRANEF: 876; SEDE: 3; SUPORTE > PGCP: 1; nome de entidade ausente: 3 |
| Usuarios, grupos, categorias, documentos | HTTP 403 ERROR_RIGHT_MISSING |
| Problemas, mudancas e validacoes | HTTP 403 ERROR_RIGHT_MISSING |
| Colecoes gerais de tarefas, acompanhamentos e solucoes | Consultaveis; isso nao comprova direito de gravacao nem direito sobre todo chamado |
| Base de conhecimento | Consultavel; isso nao comprova direito de alteracao |
| Ticket/5201 e Ticket/5202 | HTTP 404 ERROR_ITEM_NOT_FOUND |
| Ticket/6303 | HTTP 403 ERROR_RIGHT_MISSING nesta consulta; em 03/11, no Rails, foi legivel |

Esses totais representam consultas diferentes, em momentos e filtros distintos. Nao afirmar que 884 seja o total administrativo de toda a base. A diferenca 884/883, o nome ausente de tres entidades e a divergencia entre busca e detalhe precisam ser reconciliados antes de declarar cobertura completa. O bit de leitura global interpretado pelo conector atual nao foi anunciado no perfil, mas isso nao substitui verificar as permissoes efetivas de cada recurso.

Nenhum chamado, permissao, perfil ou cadastro de negocio foi alterado no GLPI. Os JSONs publicos conservam apenas contagens, identificadores, nomes de entidades e resultados tecnicos, sem tokens, descricoes de chamados ou configuracao completa do servidor.

## O que existe hoje

O cliente GLPI suporta GET e abertura de Ticket. O conector implementa lista paginada, detalhe, leitura de acompanhamentos/tarefas, abertura com recibo duravel, reconciliacao, relatorio e CSV. Credenciais sao cifradas por Account. Ha mapeamentos de entidade para unidade e de AccountUser para identidade GLPI, com isolamento de conta e rechecagem de acesso.

O detalhe solicita somente a faixa 0-99 de acompanhamentos/tarefas. O relatorio/CSV recusam mais de 10.000 chamados. A lista exclui a lixeira e pode consultar diferentes status e periodos. A busca textual atual consulta o titulo. A normalizacao conserva apenas um subconjunto de campos. Categorias sao cadastradas no mapeamento da conexao, sem descoberta automatica completa.

O dashboard, a fila operacional e os controladores nativos trabalham com JrcServiceDesk::Ticket, TicketTask, TicketApproval e Incident locais. Eles nao operam chamados GLPI apenas porque a conexao foi configurada. O novo trabalho deve conectar esses fluxos a uma origem de dados explicita.

## Abordagens consideradas

1. **GLPI como origem oficial, com adaptadores no Service Desk e indice local para leitura. Recomendada.** As telas usam contratos comuns; comandos sao executados no GLPI; indices e agregados locais sao derivados, com cobertura e atualizacao identificadas. Mantem o numero, as regras e os registros do GLPI como referencia.
2. **Copiar chamados para registros nativos editaveis e sincronizar nos dois sentidos.** Reaproveita alguns fluxos locais, mas exige resolver duplicacao de IDs, calendarios, SLA, notificacoes e edicoes concorrentes nas duas bases. Introduz uma segunda origem editavel, que nao e necessaria para o pedido.

A primeira abordagem foi aprovada pelo responsavel em 04/11/2026, junto com o escopo de implementacao, testes, publicacao e implantacao somente na Branef.

## Limite funcional de “todas as APIs”

Cobrir todas as operacoes de Service Desk que tenham correspondencia nas APIs disponiveis no GLPI 10.0.18 e nas extensoes realmente instaladas. Cada item deve ter estado documentado: existente, a implementar, bloqueado por permissao, dependente de homologacao ou sem correspondencia na origem. A disponibilidade de uma API nao implica autorizacao para usa-la.

O escopo inclui chamados, atores, categorias, tarefas, acompanhamentos, documentos, solucoes, validacoes, SLA, historico, problemas/mudancas vinculados, conhecimento e recursos vinculados aos atendimentos. Administracao geral do servidor GLPI, inventario completo de ativos sem relacao com o atendimento e funcoes de plugins desconhecidos precisam de descoberta e escopo especificos; nao serao anunciadas como integradas automaticamente.

Para fechar o criterio de entrega, o manifesto de capacidades devera identificar os verbos obrigatorios de cada familia:

- Chamado: listar, pesquisar, detalhar, criar, editar campos, atribuir atores, transferir, mudar prioridade, colocar/retirar pendencia, solucionar, fechar, reabrir e consultar historico.
- Acompanhamento: listar integralmente, publicar e editar/retirar quando a API e os direitos permitirem; manter a distincao publico/privado.
- Tarefa: listar, criar, editar planejamento/executor/duracao/estado e excluir quando permitido.
- Documento: listar, baixar, enviar, associar e retirar vinculo quando permitido; excluir arquivo compartilhado nao pode ser confundido com retirar um vinculo.
- Validacao: listar, solicitar e decidir para os atores que podem efetivamente validar na origem.
- Problema e mudanca: listar, detalhar, criar, editar, atribuir e operar as transicoes e os vinculos expostos pela API instalada.
- Conhecimento: pesquisar, detalhar, criar, editar e vincular no escopo autorizado. Exclusao exige capacidade administrativa especifica.
- Recurso vinculado: pesquisar, consultar, associar e desassociar ativos nos atendimentos; nao inclui administracao completa do parque.
- Catalogos: descobrir e usar categorias, usuarios, grupos, modelos e campos obrigatorios; permitir manutencao de categorias/modelos somente onde houver operacao GLPI e perfil administrativo correspondente.
- Indicadores: contagens, backlog, periodos, prazos/SLA, satisfacao disponivel, filtros e exportacao integral.

Para cada verbo, separar “suportado pelo conector”, “permitido para o operador” e “homologado”. Os verbos acima sao obrigatorios quando a API instalada os oferece. Nao podem ser simplesmente adiados como opcionais para declarar entrega completa. Operacoes sem correspondencia real, como um status nativo customizado sem equivalente GLPI, ficam identificadas como nao aplicaveis, sem serem convertidas silenciosamente em outra operacao. Estado bloqueado por permissao continua sendo pendencia de homologacao do ambiente, mesmo se o codigo correspondente passar no laboratorio.

## Matriz funcional

Os tipos abaixo sao familias a validar na versao instalada; relacoes, campos e verbos devem ser conferidos antes de implementar cada comando.

| Area do Service Desk | Origem/operacao GLPI | Trabalho proposto |
|---|---|---|
| Visao geral e cockpit | Busca de Ticket, entidades, status, prazos | Mesma origem e mesmo escopo da lista; contagens por entidade, status, prioridade, periodo e responsavel |
| Chamados e pesquisa | Ticket e search/Ticket | Todas as entidades aprovadas, incluindo ID 0; numero, titulo e filtros compativeis; paginacao completa |
| Minha fila e responsaveis | Ticket_User, Group_Ticket, User e Group | Descobrir atores, mapear operadores e grupos, assumir e atribuir conforme direitos |
| Edicao e prioridade | Atualizacao de Ticket | Campos permitidos, categoria, urgencia, impacto e prioridade segundo as regras da origem |
| Transferencia | Entidade/grupo/tecnico e regras aplicaveis do GLPI | Conferir destino e permissao antes de enviar; revalidar acesso depois |
| Historico e acompanhamentos | ITILFollowup e historico disponivel | Paginar integralmente; ler, publicar e alterar somente com as capacidades correspondentes |
| Tarefas e apontamentos | TicketTask | Planejamento, executor, duracao e estados com leitura e gravacao homologadas |
| Anexos | Document, Document_Item e rotas oficiais de arquivo | Listar, baixar e enviar pelo backend, com autorizacao por chamado e documento |
| Solucao e ciclo de vida | ITILSolution, Ticket e regras de status | Solucionar, fechar e reabrir respeitando validacoes, campos obrigatorios e transicoes da origem |
| Aprovacoes | TicketValidation e recursos disponiveis | Solicitar, visualizar e decidir validacoes apenas para identidades habilitadas |
| SLA e prazos | Prazos, SLA/OLA, calendarios e dados do chamado | Usar os valores da origem; nao aplicar automaticamente o relogio nativo a um chamado remoto |
| Problemas e mudancas | Problem, Change e relacoes de Ticket | Integrar leitura, vinculos e operacoes suportadas; incidentes de Ticket nao devem ser confundidos com Problem |
| Conhecimento | KnowbaseItem e categorias relacionadas | Pesquisa e vinculo no atendimento, com edicao somente se homologada |
| Recursos do atendimento | Item_Ticket e tipos de ativos efetivamente usados | Consultar e vincular recursos autorizados, sem prometer todo o inventario administrativo |
| Satisfacao e indicadores | TicketSatisfaction e dados realmente disponiveis | Calcular somente com dados e permissao; indisponivel nao pode virar nota zero |
| Relatorios e CSV | Mesmo conjunto autorizado dos chamados | Exportacao em segundo plano, sem corte silencioso; historico de cobertura e filtros |
| Conversas JRC e NICO | Vinculo JRC com referencia remota | Associacoes locais por origem/ID GLPI; toda acao remota usa o mesmo autorizador do Service Desk |
| Lixeira e exclusao | Capacidades de exclusao/restauracao disponiveis | Fluxo administrativo separado e confirmado por registro; nenhuma exclusao real em massa durante a implantacao |

## Arquitetura e contratos

### Fonte por conta

Acrescentar selecao de origem por Account, mantendo a origem nativa como padrao para as instalacoes existentes. A Branef 3 usara GLPI nas telas operacionais. O identificador de conta deve ser configuracao de runtime, sem condicoes fixas de cliente no codigo do produto. A origem nao pode ser escolhida pelo navegador para contornar a conta autenticada.

Criar contratos internos para consulta de lista, detalhe, relacoes, capacidades, indicadores e execucao de comandos. O adaptador nativo conserva o comportamento atual; o adaptador GLPI usa o cliente HTTP existente, ampliado com operacoes tipadas. Preservar os contratos externos existentes ou versionar explicitamente novas respostas. Nao expor um proxy generico que aceite URL ou tipo arbitrario do navegador.

### Identidade e armazenamento derivado

Toda referencia remota usa (account_id, connection_id, itemtype, remote_id), com entity_id verificado e data de alteracao da origem. Um Ticket GLPI 6303 nao pode ser confundido com um chamado nativo 6303. Nao criar automaticamente um Ticket nativo editavel para cada Ticket GLPI somente para satisfazer relacionamentos locais.

Criar projecoes de leitura para pesquisa e agregados, com indices por conta/conexao/entidade e ID remoto, estado da sincronizacao, cobertura e horario de coleta. Antes de ativar a origem, levantar os chamados locais eventualmente criados desde 03/11 e preservar sua consulta historica. Nao excluir nem converter esses registros automaticamente.

### Entidades e unidades

Escopo aprovado: raiz 0; SUPORTE e subentidades 1, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 22, 23, 24, 25; SEDE 21 e subentidades 18, 19, 20.

Proposta de migracao: conservar a unidade SUPORTE 1 e seus 16 vinculos; criar unidades para BRANEF/raiz e SEDE, vinculadas a operadora BRANEF. Os novos IDs devem ser obtidos no cadastro, nunca presumidos. Administradores autorizados consultarao o conjunto; agentes continuarao limitados as unidades e capacidades concedidas. Antes de aplicar, consultar os membros/roles atuais e mostrar a diferenca de mapeamentos e os operadores afetados. Nao conceder automaticamente aos agentes existentes acesso as unidades novas; inicialmente elas ficam restritas aos administradores autorizados da conta. A distribuicao posterior aos agentes depende de concessoes nominativas do administrador. Novas entidades devem aparecer como pendencia de mapeamento, sem acesso por curinga ou unidade inventada.

Tres registros da auditoria nao trouxeram nome de entidade na busca. Descobrir seus entity_id antes de mapear ou executar comandos. Um rotulo ausente nao autoriza atribui-los a raiz ou a SUPORTE por conveniencia.

### Permissoes e atribuicao de autoria

Uma acao exige simultaneamente acesso a conta, unidade, capacidade JRC, identidade mapeada quando aplicavel e autorizacao efetiva do GLPI. Rechecar na execucao e na entrega de anexos/exports. O uso de credencial tecnica compartilhada deve aparecer na auditoria: operador JRC iniciador e usuario tecnico efetivo no GLPI. Nao afirmar que esse mecanismo representa uma sessao pessoal do operador no GLPI.

A autenticacao continua usando os tokens cifrados no backend. O responsavel escolheu expressamente: **usuario tecnico da integracao no GLPI, com auditoria do operador no JRC**. Essa decisao se aplica aos comandos e as validacoes. Nao solicitar um token pessoal a cada operador como requisito desta entrega. Um mapeamento numerico de identidade nao concede delegacao nem pode fabricar autoria pessoal no GLPI.

O usuario tecnico continua sujeito aos direitos efetivos da origem: uma validacao atribuida a outra identidade e nao autorizada para esse usuario deve ser recusada e explicada, mesmo que o operador tenha capacidade de aprovacao no JRC. Se futuramente for exigida autoria pessoal no GLPI, isso sera uma mudanca de autenticacao, fora desta decisao.

As capacidades apresentadas na interface devem distinguir permitido, negado e ainda nao homologado. HTTP 403 nao pode virar lista vazia; HTTP 404 nao comprova exclusao. O perfil Suporte deve ser revisado pelo administrador GLPI para as familias hoje bloqueadas. Nao solicitar Super Admin GLPI como atalho.

### Leitura completa e sincronizacao

Percorrer a paginacao com limites anunciados pela origem. Incluir abertos, pendentes, solucionados, fechados e historicos dentro do escopo; datas e ano nao terao corte oculto. Lixeira e conteudo privado exigem permissoes e filtros separados. A carga inicial deve registrar cobertura por entidade, IDs distintos, paginas processadas, falhas e horario. A primeira fase deve explicar a diferenca 884/883 e a relacao entre busca e detalhe.

Leituras de tarefas, acompanhamentos e demais relacoes devem paginar alem de 100 registros. As colecoes gerais de ITILSolution/ITILFollowup nao podem ser despejadas na conta sem checar o chamado/entidade a que pertencem.

O indice pode atualizar por date_mod e ID, com verificacoes periodicas de cobertura. Uma perda de acesso nao equivale a exclusao. As consultas do GLPI nao fornecem automaticamente um snapshot transacional entre paginas: registrar alteracoes concorrentes e reprocessar/reconciliar, sem anunciar consistencia atomica inexistente.

Paineis e indicadores mostram data da ultima atualizacao e cobertura; dados parciais ou antigos ficam identificados. Em indisponibilidade, dados locais nao podem se apresentar como atualizados. Acoes remotas exigem nova validacao na origem. Relatorios extensos usam tarefas em segundo plano, progresso, cancelamento e resultado completo por escopo; eliminar o teto atual de 10 mil como limite funcional, mantendo limites operacionais explicitos por lote e recurso.

### Comandos, concorrencia e auditoria

Estender o recibo duravel existente para operacao, objeto-alvo, entidade, identidade, fingerprint, estado, erro e resultado remoto. A chave de idempotencia deve distinguir operacao e alvo. Persistir intencao antes da chamada de rede. Uma resposta ambigua nao sera reenviada automaticamente; deve haver reconciliacao conforme o recurso e sua correlacao verificavel.

Atualizar somente os campos solicitados. Comparar a revisao/data_mod antes da escrita e conferir o resultado depois. Serializar comandos locais para o mesmo objeto. Isso nao torna atomica uma disputa com edicoes feitas diretamente no GLPI: a API generica V1 nao garante compare-and-swap. Se for exigida exclusao total desse risco, avaliar extensao GLPI compativel; nao prometer travamento que a origem nao oferece.

As operacoes reais devem registrar sucesso somente depois de confirmacao da origem. Distinguir recusado, indisponivel, conflito e resultado indeterminado. E-mails e eventos nao podem ser duplicados por repetir o mesmo comando. Validar as regras de notificacao e SLA da origem em homologacao.

Regras de automacao, formularios e configuracoes JRC devem declarar se atuam sobre recursos locais ou comandos GLPI. Para chamados remotos, uma automacao usa o mesmo executor tipado e as mesmas permissoes de uma acao manual; nao pode finalizar apenas a projecao local. Estados fixos, modelos, campos obrigatorios e calendarios da origem prevalecem. Configuracao nativa sem correspondente GLPI fica explicitamente separada. As notificacoes operacionais do chamado pertencem ao GLPI; notificacoes JRC adicionais precisam ser configuradas com finalidade distinta, evitando duplicacao automatica de mensagens.

### Arquivos e conteudo

Arquivos GLPI permanecem na origem e sao entregues por rota autenticada do backend JRC. Uploads do fluxo GLPI devem chegar ao GLPI pela API de documentos/associacao, com tamanho, tipo e capacidade validados. O bucket JRC de 15 GiB nao recebera automaticamente uma copia de todos os anexos GLPI. Anexos nativos JRC continuam no armazenamento atual.

Sanitizar conteudo e links sem perder texto, tabelas e referencias necessarias ao atendimento. Nenhuma URL extraida da descricao pode receber tokens. Autorizar o documento pelo chamado, preservar notas privadas e validar cada download; um ID de documento isolado nao basta.

## Entrega em etapas, com o mesmo objetivo final

1. Reconciliar escopo e permissoes: confirmar revisao do ambiente, 21 mapeamentos, entidades ausentes, diferenca de contagens e leitura de detalhes. Preparar ajuste de perfil para a administracao GLPI.
2. Construir a camada de origem e leitura completa: lista, detalhe, pesquisa, filas, responsaveis, timeline e anexos; colocar dashboard e relatorios sobre esse conjunto.
3. Implementar comandos remotos: edicao, atribuicao, acompanhamentos, tarefas, documentos, solucoes, status e validacoes, com recibos, direitos e concorrencia.
4. Conectar modulos relacionados: problemas, mudancas, conhecimento, recursos vinculados e satisfacao conforme descoberta e permissoes da versao instalada.
5. Homologar fluxos completos, publicar imagem por SHA, implantar somente na Branef e verificar a revisao em execucao, paineis, registros e comportamento de erro.

Nenhuma etapa parcial sera declarada integracao completa. Uma familia bloqueada deve ficar visivelmente indisponivel e registrada como pendencia, sem simulacao de sucesso. O cronograma depende do ajuste das permissoes e da homologacao de escrita.

## Criterios de aceitacao

Decisao tecnica proposta para os testes: laboratorio GLPI 10.0.18 isolado e descartavel, com dados sinteticos, cobrindo os verbos e diferentes perfis sem copiar chamados reais. Usar simulacao para falhas de rede e concorrencia. A homologacao do cliente continua distinta: repetir leituras a partir do Rails e validar a matriz de acesso do perfil real. Escritas reais no cliente so depois de identificar ambiente/registro de teste e autorizacao especifica; o laboratorio nao sera apresentado como comprovacao de escrita na producao Branef.

- Os 21 IDs aprovados estao mapeados, incluindo 0, e os registros visiveis sao reconciliados com a origem por entidade/status/periodo, com explicacao de diferencas.
- Dashboard, lista, fila, detalhe, historico, relatorios e export usam o mesmo escopo autorizado, com dados e cobertura identificados.
- Historicos com mais de 100 eventos e exports com mais de 10 mil registros sao exercitados em bases de teste.
- Operacoes aparecem somente quando correspondem a API e direitos reais; cada resultado e confirmado na origem.
- Isolamento de Account, revogacao, unidades, notas privadas, acesso a documentos e autoria tecnica/pessoal sao exercitados nos testes.
- Timeouts antes/depois da escrita, reenvio da mesma chave, concorrencia e reconciliacao nao causam duplicacoes ou falso sucesso.
- Testes de escrita usam GLPI de homologacao ou registros de teste explicitamente autorizados. Os chamados reais da operacao nao sao usados indiscriminadamente.
- A regressao da origem nativa continua passando. A imagem e identificada por SHA/digest e o ambiente em execucao e conferido depois do deploy.
- Matriz final identifica o que esta comprovado, o que foi simulado no CI e o que depende de permissao/homologacao real. “Todas as APIs” nao sera um rotulo sem lista verificavel.

## Condicoes externas e decisoes propostas

O administrador GLPI precisa habilitar o acesso necessario a usuarios, grupos, categorias, documentos, validacoes e modulos contratados, bem como leitura efetiva dos detalhes dos chamados no escopo. Deve confirmar existencia/entidade/visibilidade de 5201 e 5202. Para as escritas, sera necessario GLPI de homologacao ou identificacao dos registros de teste autorizados e das operacoes permitidas.

Escolhas tecnicas propostas: GLPI como origem oficial; API V1 na versao 10.0.18; indice local derivado; migracao de mapeamentos por ramo; laboratorio isolado com dados sinteticos; adaptadores preservando a origem nativa das outras contas. Decisao de identidade ja confirmada pelo responsavel: credencial tecnica existente com auditoria explicita do operador no JRC.

A aprovacao desta proposta permite elaborar o plano detalhado e implementar o produto. Publicacao de imagem e implantacao desta ampliacao devem constar da aprovacao; a autorizacao anterior era para a correcao de resultado vazio. Alteracoes administrativas na origem e testes de escrita em dados reais continuam dependentes da definicao do ambiente/registros apropriados.

## Referencias e evidencias

- Auditoria atual: output/evidencias/glpi-auditoria-ampliacao-20261104.json.
- Cobertura atual: output/evidencias/glpi-cobertura-21-entidades-20261104.json.
- Codigo inspecionado: https://github.com/ClaudioHideki/Jrconversas_Branef_GLPI/tree/86f64ca467fc18930105c9157bb9e3f933aa2f78/app/services/jrc_service_desk/glpi
- Controlador: https://github.com/ClaudioHideki/Jrconversas_Branef_GLPI/blob/86f64ca467fc18930105c9157bb9e3f933aa2f78/app/controllers/api/v1/accounts/jrc_service_desk/glpi_controller.rb
- API V1: https://help.glpi-project.org/documentation/modules/configuration/general/api/api
- API V2 e sua autenticacao distinta: https://help.glpi-project.org/documentation/modules/configuration/general/api/restful-api-v2

As credenciais do manual nao fazem parte desta proposta nem dos arquivos de evidencia. O relatorio de 03/11 permanece como registro da implantacao anterior; esta proposta nao altera seus resultados historicos.
