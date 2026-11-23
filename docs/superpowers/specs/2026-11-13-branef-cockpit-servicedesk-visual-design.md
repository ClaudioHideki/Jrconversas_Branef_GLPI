# Branef: Cockpit e renovação visual do Service Desk

Data: 13/11/2026, America/Sao_Paulo.
Estado: desenho e prévia aprovados pelo usuário em 13/11/2026 para implementação e testes. Publicação e implantação serão uma etapa posterior.

## Pedido e decisões do usuário

- Retirar a entrada WhatsApp Calling da navegação da Branef.
- Manter Atendimento, colocando Cockpit antes dele.
- Acrescentar ao Cockpit um card de chamados com dados reais do GLPI.
- Melhorar cores, hierarquia, legibilidade, pesquisa e filtros em todas as telas do Service Desk.
- Manter as telas separadas, conforme escolha explícita do usuário.
- Apresentar uma prévia navegável local com dados demonstrativos identificados, antes de implementar.

O objetivo é reconhecer rapidamente o que precisa de atendimento, pesquisar e compreender os dados. A proposta preserva os contratos e as permissões existentes. Não muda a árvore da URA, o Broker, o NICO, os agentes, os times, credenciais, SLAs contratuais ou o GLPI do cliente.

## Abordagens consideradas

1. **Manter as páginas e aplicar uma linguagem visual compartilhada. Escolhida pelo usuário.** Preserva rotas e hábitos existentes; os componentes comuns propagam consistência para lista, visão geral, fila, SLA, responsáveis, relatórios e recursos operacionais.
2. **Central unificada com abas.** Reduz a navegação, mas altera a organização do trabalho e concentra mais estados numa tela. O usuário preferiu manter as telas atuais.

Uma alteração somente de paleta não resolve a repetição de avisos, a semântica do SLA ou os estados de erro. Esses pontos fazem parte do desenho escolhido.

## Base e evidências consultadas

- Oito imagens do usuário: navegação, Cockpit, listas GLPI, visão geral, Minha fila e SLA.
- GitHub consultado em 13/11: referência mais recente retornada para Branef `d1b47c944f5c44eb73f13c0793b79ce83c4f360a`; núcleo LAB2 `d8a83b824b11cc68ddbbce7c79681f368051fb70`.
- Manifesto de coordenação `CONSOLIDACAO-20261109.json`, atualizado em 10/11: Branef deriva desse núcleo e mantém GLPI exclusivo.
- Imagem Branef registrada e preservada na reaplicação de configuração NICO em 13/11: `sha256:8de4d63f0ee17d8d949218fd622d6beba76e63afd35b16593bef538fd3d7b874`. Revalidar no servidor antes de qualquer futura implantação de produto.
- O checkout antigo `.private/branef-glpi-integral` está em `b7ae0c0` e possui trabalho documental não publicado. Foi consultado com `git show` da revisão atual; não deve ser usado como base antiga de implementação.

Arquivos relevantes da revisão Branef:

- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` e `temporaryVisibility.js`;
- `app/javascript/dashboard/routes/dashboard/jrcService/JrcCockpit.vue`;
- `app/services/jrc_ai/cockpit_metrics_service.rb`;
- `app/javascript/dashboard/routes/dashboard/serviceDesk/ServiceDeskLayout.vue`;
- `glpi/GlpiServiceDesk.vue`, `GlpiFilters.vue`, `GlpiCoverage.vue`, `GlpiOverview.vue`, `GlpiTicketWorkspace.vue`, `GlpiResourceBoard.vue`, `GlpiSync.vue`;
- `helpers/glpiScreens.js` e os testes existentes de origem, navegação e controles.

## Diagnóstico

1. Na navegação unificada, o grupo de atendimento coloca Inbox antes do Cockpit. WhatsApp Calling é incluído com `ignoreFeatureFlag`.
2. O Cockpit não contém métrica de chamados GLPI. Seu SLA é uma estimativa de espera das conversas, com limiar fixo de oito minutos; retorna 100 quando não há conversas abertas. Não representa o SLA dos tickets.
3. O contêiner GLPI usa o mesmo título genérico em várias páginas e lista todos os erros separadamente.
4. O painel administrativo de coleta ocupa grande área antes dos dados. Cobertura também é exibida pelos componentes filhos, repetindo informações.
5. Filtros têm rótulos pequenos, poucos sinais de seleção e não oferecem uma ação clara de limpar.
6. Listas e relatórios exibem estados/prioridades como texto sem diferenciação, datas técnicas, entidades com escape aparente e identificadores sem nome humano.
7. `Minha fila` usa um filtro de identidade GLPI. Um `forbidden` não é evidência suficiente para afirmar a causa exata; a orientação deve pedir conferência de identidade e permissões.
8. As telas SLA também consultam catálogos de SLA/calendários. `ERROR_RIGHT_MISSING` não pode ser tratado como ausência de SLA nem escondido pela nova apresentação.

## Navegação

- No grupo Atendimento: **Cockpit → Atendimento**. Isso altera a ordem do menu; não altera automaticamente a rota pós-login.
- Ocultar a entrada WhatsApp Calling e seus atalhos equivalentes de navegação na Branef. Não excluir dados nem remover transporte WhatsApp, Broker, caixa API ou funcionalidades compartilhadas da plataforma.
- A visibilidade deve ser configurável por conta/módulo; não codificar o ID 3 ou o nome Branef em componentes genéricos.
- Preservar os outros itens e os controles de autorização existentes. A ausência de menu não substitui uma permissão de backend.

## Card de chamados no Cockpit

Apresentação proposta:

- Título **Chamados GLPI**, ícone de ticket e destaque azul/índigo.
- Quantidade de tickets no escopo autorizado e período indicado; não apresentar o número como total global da Branef.
- Resumo de ativos e prazo excedido somente se o contrato consultado fornecer dados suficientes e a contagem respeitar os filtros.
- Origem GLPI, momento da última coleta e indicação de cobertura completa/parcial/indisponível.
- Clique abre a tela de chamados GLPI mantendo o período/filtros realmente suportados por essa consulta. Não transformar silenciosamente um período de abertura em período de atividade.
- Carregamento, vazio válido, parcial, falta de permissão e indisponibilidade são estados distintos. Falta de acesso não aparece como zero.
- Falha do GLPI não derruba os outros indicadores do Cockpit.
- A abertura do Cockpit não dispara uma coleta integral nem grava no GLPI. Reutilizar o contrato de relatório/leitura autorizado e sua projeção, quando aplicável.
- O agregado deve ser produzido a partir do escopo autorizado no servidor; não descarregar todos os tickets no navegador apenas para contá-los. O planejamento definirá o adaptador entre o Cockpit genérico e o módulo específico.

Separar o indicador atual de espera: usar rótulo **Espera das conversas (estimativa)** ou equivalente claro. Sem amostra, exibir “Sem amostra”, não “100% de SLA GLPI”. O valor não deve ser combinado com o SLA dos tickets.

## Linguagem visual

- Manter a identidade JRC: navegação azul escura, fundo claro, espaços regulares e superfícies brancas.
- Cabeçalho próprio por tela: título, uma frase sobre a finalidade, escopo e ações principais.
- Azul para entrada/atividade, âmbar para pendência/atenção, vermelho para atraso/criticidade, verde para solução/fechamento e neutro para indisponibilidade/ausência de prazo. Uso moderado de violeta em fila e encaminhamento.
- Cor sempre acompanhada de rótulo e, quando útil, ícone. Não depender apenas da percepção de cor.
- Estados GLPI mantêm seus significados: Novo; Em atendimento atribuído; Em atendimento planejado; Pendente; Solucionado; Fechado. Atraso é um indicador de prazo, não um status remoto inventado.
- Prioridades mantêm as seis categorias da API. Criticidade da árvore não é remapeada pela aparência.
- Aumentar a legibilidade dos rótulos, valores e contrastes sem comprimir tabelas por redução excessiva de fonte.
- Usar componentes e Tailwind existentes na implementação. Sem troca de framework ou inclusão de biblioteca visual pesada.
- Respeitar tema claro/escuro, foco visível, teclado, rótulos acessíveis, mensagens de status e movimento reduzido.
- Tabelas devem rolar horizontalmente em telas estreitas sem causar rolagem lateral na página inteira. Filtros empilham no celular.

## Filtros e tabelas

- Entidade com nome legível, pesquisa por número/título, status, prioridade e intervalo de abertura são os controles já suportados.
- Exibir filtros aplicados como marcadores removíveis, botão **Limpar filtros**, total do resultado e estado de carregamento.
- Preservar filtros na navegação adequada, revalidando ao trocar conta, usuário ou origem. Evitar misturar dados de consultas anteriores com novos filtros.
- Responsável, grupo e filtros rápidos adicionais só serão oferecidos se houver suporte real no contrato. A prévia não autoriza adicionar parâmetros que o backend ignora.
- “Meus chamados”, “Pendentes” e “Prazo excedido” precisam indicar precisamente o escopo; não filtrar apenas a página atual e apresentar o resultado como total.
- Número bem identificado, título com hierarquia, entidade em texto simples, status e prioridade em etiquetas, prazo com data/hora e marcador de atraso quando comprovado.
- Exibir datas no formato brasileiro e no fuso configurado, preservando a distinção entre data GLPI e data UTC de observação. Não depender do fuso do navegador para interpretar timestamps sem offset.
- Corrigir entidades com `&gt;` e rótulos como `unclassified` com formatação segura de texto. Não usar HTML remoto como marcação nem inventar nomes para IDs desconhecidos. Quando um catálogo não estiver autorizado, manter o ID com explicação.
- Manter paginação, ordenação suportada, abertura do detalhe e exportação no mesmo escopo autorizado.

## Coleta, cobertura e erros

- Substituir a grande área de coleta por uma faixa compacta: fonte, última coleta, estado de cobertura e ações administrativas permitidas.
- Manter **Atualizar consulta** separado de **Coletar dados da origem**; a segunda é uma operação administrativa específica, nunca automática por abrir um card.
- Detalhes técnicos, intervalo percorrido, códigos de origem e ressalva de consulta não atômica ficam acessíveis em área expansível.
- Cobertura parcial, falha e dado indisponível permanecem visíveis. A ressalva não pode ser removida ou virar um selo genérico de “tudo atualizado”.
- Consolidar alertas repetidos com contagem/detalhes por operação, sem ocultar falhas distintas.
- `ERROR_RIGHT_MISSING`: explicar que o perfil técnico não tem a permissão necessária à consulta identificada.
- `forbidden`: informar que o acesso não está disponível e orientar conferência de vínculo de usuário/entidade/permissões, sem diagnosticar uma causa não comprovada.
- Oferecer ações coerentes com a permissão: tentar novamente, consultar detalhes, ou acessar configuração apenas para quem pode fazê-lo.
- Nenhuma alteração de UI concede direitos GLPI, altera tokens ou habilita escrita remota.

## Conteúdo por tela

| Tela | Hierarquia proposta |
| --- | --- |
| Chamados GLPI | Consulta de entrada, filtros, total autorizado e tabela com estado/prioridade/prazo legíveis. |
| Visão geral | Indicadores, distribuição por status/prioridade/entidade e responsáveis com nomes disponíveis. Gráficos derivados dos dados, com valores e legenda. |
| Chamados | Área de trabalho da lista e acesso ao detalhe/abertura, com identidade visual igual e título específico. Não criar outra fonte de tickets. |
| Minha fila | Escopo pessoal explícito, estados de identidade/permissão e lista priorizada apenas quando a origem permitir. |
| SLA | Com prazo, prazo excedido e sem prazo separados; prazos, catálogos e calendários com seus próprios estados de acesso. Sem percentual artificial. |
| Responsáveis | Pessoas e equipes autorizadas, identificação legível e contexto; contagens/carga apenas se fornecidas por consulta autorizada. |
| Relatórios | Período e filtros evidentes, gráficos/resumos reconciliados, exportação com progresso, cobertura e filtros do recibo. Não confundir o filtro atual com o da exportação já iniciada. |
| Operação | Padrão visual compartilhado para os recursos existentes: filas/grupos, tarefas, incidentes e demais recursos oferecidos pelas rotas/capacidades reais. Ações disponíveis, não suportadas ou recusadas ficam distintas. |
| Detalhes e formulários | Seções claras para identificação, classificação, responsáveis, prazos e histórico; labels, ajuda e validação visíveis. Mantém confirmações, idempotência e reconciliação. |

Serviços/governança, gestão e configurações existentes devem receber os componentes compartilhados aplicáveis, sem inventar operações GLPI novas. Uma matriz de rotas no plano deve garantir que nenhum recurso existente fique sem acesso após a reforma.

## Fronteiras técnicas e implantação

- Mudanças genéricas de navegação, indicadores e apresentação pertencem ao núcleo LAB2; configurações da conta e a extensão GLPI permanecem específicas.
- O núcleo deve oferecer um ponto de integração neutro para métricas de chamados, sem carregar código, endpoint fixo ou credenciais GLPI da Branef.
- Implementação parte das referências atuais, em isolamento adequado, e preserva o trabalho concorrente. O plano identificará os commits e os arquivos por produto.
- A primeira implantação solicitada será somente na Branef, após código revisado, testes e imagem verificáveis e autorização correspondente. Nenhum deploy automático no LAB2/Grupo JRC/Broker ou em outros clientes.
- Nenhum downgrade, reset/clean, troca de chaves, migração GLPI ou replay de mensagens.
- A preparação NICO de 13/11, o modo interno e o bloqueio de delegação são preservados no Compose efetivo.

## Prévia aprovada para avaliação

- HTML local e descartável, independente de Rails/Broker/GLPI.
- Dados sintéticos marcados continuamente como demonstração; nenhum token, nome de cliente, consulta externa ou escrita remota.
- Navegar entre Cockpit e as telas solicitadas; exercitar filtros, etiquetas, detalhe e exportação demonstrativa.
- Simular estados: dados disponíveis, vazio, parcial, falta de permissão e indisponibilidade.
- A prévia demonstra a aparência e interações, não comprova a implementação nem resolve os erros GLPI atuais.

## Aceitação da futura implementação

1. Cockpit aparece antes de Atendimento; WhatsApp Calling não aparece na navegação da Branef. Os demais clientes não perdem módulos.
2. Card GLPI mostra o total/estado autorizado correto e abre a consulta correspondente. Zero, falta de acesso, parcial e falha não são confundidos.
3. O indicador de espera das conversas não é apresentado como SLA GLPI.
4. As telas têm títulos próprios, apresentação consistente e campos mais legíveis; status/prioridade mantêm semântica e texto.
5. Filtros, paginação e exportação preservam escopo e mostram o conjunto a que se referem. Troca de conta/origem não vaza nem reapresenta dados antigos.
6. Coleta administrativa e informações de cobertura continuam disponíveis, sem dominar todas as telas ou repetir alertas.
7. Erros de permissão não são ocultados, nem geram zeros ou funcionalidades fictícias.
8. Entidades, nomes e datas são formatados com segurança e fuso correto, sem HTML remoto executável.
9. Conferência visual em desktop e largura estreita, navegação por teclado e contraste, incluindo estados vazios/parciais/recusados.
10. Testes significativos de contrato/escopo e regressão das rotas alteradas; build/lint adequados. Gates do SHA final antes de publicar imagem; homologação de UI implantada separada dos testes locais.

## Fora desta alteração

Liberação de perfil GLPI, concessão de caixas a agentes, pareamento do número oficial, ativação da URA, criação/edição de tickets reais, SMTP, telefonia/PABX e contratação/cobrança de IA. A pendência de origem continua pendente mesmo com a nova interface.

## Autorização recebida

O usuário escolheu manter as telas, avaliou a prévia e respondeu “Aprovar implementação e testes”. A autorização cobre o trabalho local e sua validação; não inclui publicar ou implantar esta revisão. Aprovação da aparência não comprova funcionamento produtivo.

## Revisão do desenho e da prévia

- Revisão independente do desenho concluída em 13/11: `nothing important left`.
- Prévia local v3: navegação entre as telas; card GLPI; busca por número com um resultado; marcador de filtro e limpeza; detalhe com foco inicial e fechamento por Escape; fila pessoal com seis registros sintéticos do operador; falta de permissão com valores indisponíveis, não zeros; cobertura parcial com oito registros; SLA com três prazos excedidos destacados; telas de responsáveis, relatórios e operação; consulta vazia.
- Verificação de sintaxe JavaScript aprovada. Não representa build, testes ou implantação do produto.
- Teste em largura estreita identificou mínimo intrínseco da grade causando rolagem lateral; corrigido na prévia v3 e reconferido. A tabela mantém a própria rolagem horizontal.
- A versão estática pode ser aberta sem servidor e não possui URLs de produção, credenciais ou dependências de rede.
