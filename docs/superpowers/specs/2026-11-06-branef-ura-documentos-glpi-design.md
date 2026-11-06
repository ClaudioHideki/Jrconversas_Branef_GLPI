# Branef: URA e atendimento conforme os documentos

Data: 06/11/2026, America/Sao_Paulo.
Estado: desenho revisado e aprovado pelo usuário em 06/11/2026, incluindo triagem N2/N3, dois modos de abertura, 48 horas corridas após aviso entregue com cancelamento por resposta e sem pesquisa nesse fechamento. Implementação autorizada; ainda sem publicação de nova versão do robô para este escopo.

## Objetivo e decisões do usuário

Aplicar ao atendimento WhatsApp da Branef os fluxos dos quatro documentos recebidos, mantendo o Flow do Broker como executor da URA e o JRC Conversas como área de trabalho dos agentes. O GLPI continua como origem oficial dos chamados. Incluir PGLS, triagem, conteúdos municipais, equipes, classificação, prazos, acompanhamento e conclusão. Conta de destino: Branef 3, sem alterar Grupo JRC, LAB ou outros clientes.

O usuário escolheu em 06/11 a aba **Proposta - Nova árvore**, incluindo as exceções de Maringá, como referência de SLA. Essa decisão resolve a divergência de valores com a aba SLA. Não define dias úteis/corridos, calendário, primeira resposta versus solução ou pausa do relógio.

Decisões anteriores preservadas: todas as entidades da Branef disponíveis aos operadores autorizados; usuário técnico no GLPI, com auditoria da ação no JRC; suporte aos dois momentos de criação (após qualificação ou na passagem humana). O teste no canal Welton permanece sem criar ou alterar chamados reais. O acesso amplo do operador não é repassado ao contato WhatsApp.

## Fontes e situação atual

Fontes: Árvore de atendimento_Proposta Branef.xlsx (três abas), Perfis GLPI.xlsx (Planilha1), Resposta para Maringá (3).docx e Respostas padrões de e-mails 1 1 1 (1).docx. Os originais foram lidos sem alteração; hashes e análise estão no relatório local output/ANALISE-DOCUMENTOS-BRANEF-URA-GLPI-20261106.html. Não versionar os documentos, a lista pessoal de usuários, tokens, números WhatsApp ou conteúdo de atendimentos reais.

A versão de teste existente foi migrada dos quatro JSONs: três sistemas, 108 nós, 59 opções e nove destinos humanos ligados a um único operador de homologação. Não atende ainda ao catálogo novo de quatro sistemas. A integração WhatsApp/Broker/caixa Branef já existe; a lista do Atendimento reúne abertos e pendentes. A implantação anterior usa o commit 3d82f4862d738f443fe3babcca21ff6a740dcce7. Estes fatos são referências da etapa anterior; a execução deve conferir novamente a versão e a vinculação antes de publicar.

Inspeção do código nesta etapa:

- Broker: apps/api/src/modules/automations e packages/contracts/src contêm menus, inputs, condições, variáveis, horários, handoff, efeitos de conversa e recibos.
- O comando domain atual cobre somente create_lead, create_task e create_meeting (CRM), não criação de chamado GLPI. Não reutilizar esses comandos como se já operassem Service Desk.
- JRC: JrcFlowEffects::Authority/Apply e JrcDomainCommands::Scope validam conta, usuário de serviço, organização, integração, caixa e revisão de controle.
- JrcServiceDesk::Glpi::AutomationCommand, Destination e Execute já fornecem comandos tipados, validação de conexão/entidade, idempotência e recibos. GlpiReferenceLink associa conversas a referências remotas.
- As listas de campos de criação/edição GLPI não aceitam configuração genérica de SLA. Catálogos e uma operação tipada validada precisam ser ampliados onde necessário; não enviar campos arbitrários nem presumir que o suporte já existe.

## Abordagens

1. **Reaproveitar Flow/Broker e ampliar a entrega tipada ao Service Desk.** É a abordagem compatível com a escolha anterior do usuário de usar Flow e Broker. Menus e transporte ficam onde já funcionam; regras, vínculo e comandos GLPI ficam no JRC. Permite homologar sem habilitar escritas reais.
2. Colocar tokens e chamadas GLPI genéricas no Flow. Exigiria repetir permissões, sessões e tratamento de duplicação, separando a auditoria do executor existente. Não atende à decisão anterior de manter os segredos no servidor e as operações no Service Desk.
3. Substituir o robô pelo NICO ou copiar chamados para uma base nativa editável. Não atende ao reaproveitamento solicitado da árvore determinística e criaria uma segunda origem para chamados. Não é necessário para estes documentos.

A opção 1 mantém a plataforma já escolhida; a divisão técnica abaixo é proposta do implementador. Não mudar a identidade da empresa ou conceder acessos por inferência dos arquivos.

## Catálogo e fluxo conversacional

Catálogo por conta, versionado e publicado com referência às células de origem. Os menus devem ser gerados desse catálogo; o mesmo catálogo resolve os valores recebidos pelo backend. Não duplicar regras fixas em dois repositórios. A publicação prende uma revisão imutável do catálogo e outra do Flow; uma revisão nova não altera sessões em andamento silenciosamente.

1. Entrada pelo único número; apresentar PGCP, PGLS, SISVISA e SIVISA+.
2. Identificar secretaria/local: PGCP SESAB/SEDUR/SAEB; PGLS Salvador; SISVISA Bahia e os rótulos SGF/AVISA/SISGTES/SERR conforme catálogo; SIVISA+ Alagoinhas/Maringá/Itabuna.
3. Em SIVISA+, distinguir regulado e agente da VISA; coletar outros perfis já necessários às orientações, como responsável técnico ou procurador. Perfil declarado não concede permissão de consulta.
4. Selecionar dúvida, solicitação, BUG ou melhoria e submotivo. Oferecer orientação pertinente e caminho para atendimento humano. Permitir voltar ao menu e corrigir a classificação sem abrir novo chamado.
5. Capturar identificação (CPF ou CNPJ), e-mail e descrição antes do registro/encaminhamento, conforme Considerações A1. Não exigir novo fornecimento a cada clique se os dados já foram coletados e confirmados no episódio. Validar formato e confirmar os dados; não chamar essa validação de autenticação.
6. Para BUG, coletar impacto e urgência/evidências necessárias à classificação. O cliente descreve o problema; a matriz de criticidade exige regra publicada e possibilidade de revisão pela equipe, não adivinhação do robô.
7. Registrar ou vincular ao GLPI conforme o modo de criação; encaminhar à equipe; acompanhar no JRC. Se o mapeamento estiver incompleto, exibir falha operacional clara e permitir triagem humana, sem prometer ticket ou fila remota inexistente.
8. Após atendimento, aplicar conclusão e avaliação nas condições confirmadas. A FAQ pode resolver uma dúvida sem criar Ticket no modo de abertura humana.

As listas de secretaria/cidade na planilha são blocos visuais mesclados, não uma associação exclusiva por linha. Proposta técnica: tratá-las como dimensão independente do motivo dentro do sistema; manter cada combinação como não mapeada até relacioná-la à entidade/categoria real. Nunca concluir que SEDUR só tem BUGs ou Maringá só solicitações.

### Submotivos completos

| Sistema | Motivo | Submotivos da proposta |
|---|---|---|
| PGCP | Dúvida | Acesso e cadastro |
| PGCP | Solicitação | Perfil e acesso |
| PGCP | BUG | Prestação de contas; fluxo de caixa; contrato; convênio |
| PGCP | Melhoria | Prestação de contas; fluxo de caixa; contrato; convênio; front do sistema; regras de negócio; outros |
| PGLS | Dúvida | Acesso e cadastro; alvará; documentação; DAM; assunção |
| PGLS | Solicitação | Verificar débitos; perfil e acesso; documentação; consulta do processo; alteração cadastral |
| PGLS | BUG | Juros indevidos; assunção RT; inclusão/exclusão de documentação; outros |
| PGLS | Melhoria | Assunção RT; front do sistema; regras de negócio; outros |
| SISVISA | Dúvida | Acesso e cadastro; assunção; documentação; débitos/taxas; como utilizar o sistema; alteração de CNAE; alvará; inspeção |
| SISVISA | Solicitação | Alteração dos dados; consulta do processo; perfil e acesso |
| SISVISA | BUG | Fluxo de PBA; funcionalidades do sistema; inclusão/exclusão de documentação; outros |
| SISVISA | Melhoria | Front do sistema; regras de negócio; outros |
| SIVISA+ | Dúvida | Acesso e cadastro; alvará; documentação; emissão da guia; como utilizar o sistema; assunção |
| SIVISA+ | Solicitação | Perfil e acesso; alvará; alteração dos dados; consulta do processo |
| SIVISA+ | BUG | Funcionalidades do sistema; inclusão/exclusão de documentação; outros |
| SIVISA+ | Melhoria | Front do sistema; regras de negócio; outros |

São 65 entradas por sistema/motivo/submotivo, sem contar a multiplicação por locais/perfis. A célula D25:D26 de PGLS é um único submotivo mesclado. Os casos sem resposta documental recebem coleta e encaminhamento humano; não inventar FAQ para PGLS.

## Conteúdo e casos municipais

Maringá: perguntar inicial ou renovação. Empresa Fácil é o destino descrito para alvará inicial, alterações contratuais/cadastrais e encerramento; cadastro de estabelecimento SIVISA+ está condicionado à renovação. Assunção/baixa de RT, cadastro de usuário/RT, procurador, renovação e PBA têm orientações e oito links Notion incorporados. Solicitações de atuação local seguem para os contatos oficiais indicados, após conferir validade e adequação. Não afirmar que essa orientação executou o procedimento externo.

Os textos de e-mail viram respostas rápidas e sugestões contextuais por local/motivo. Substituir placeholders obrigatoriamente antes de enviar; assinatura e nome do sistema corretos. Respostas sobre cadastro criado/aprovado, correção aplicada, classificação de risco ou estado de processo requerem dado verificável ou confirmação do operador. O bot não inventa status de processos sanitários a partir de um chamado GLPI.

Documentação JIRA fornece roteiro de coleta de evidências e retorno, não autorização ou especificação de uma nova integração JIRA. Entregar os modelos e a indicação de escalonamento no chamado; criar/alterar issues JIRA é dependência adicional, explicitamente indisponível até configurar uma integração autorizada. Da mesma forma, não criar usuários em sistemas externos só por existir a resposta “usuário criado”.

## Filas, usuários e supervisão

Proposta: dúvida → N1; solicitação PGCP → N2; demais solicitações, BUGs e melhorias → conjunto N2/N3 conforme planilha. Quando a origem diz N2/N3, manter uma fila de triagem desse conjunto ou exigir regra específica publicada; não escolher N3 por um nome de usuário. N1=Suporte; N2=Sustentação. N3 e Gerência são filas distintas, cuja atribuição depende do mapeamento operacional.

Preparar conferência/importação da matriz de onze pessoas: sete atendentes N1/N2, um atendente N3, um administrador N3, um administrador Todas e um administrador Gerência. Não gravar nomes/e-mails no código. Normalizar espaços e detectar duplicados, distinguindo GLPI User, User JRC e AccountUser. Não criar doze usuários por duplicação de identidades existentes. Administrador da conta não equivale a Super Admin da instalação.

Criar os grupos lógicos/configurações e prévia das permissões; concessão efetiva de acesso exige correspondência com membros autorizados e direitos reais. Não enviar convites ou credenciais automaticamente nesta fase. A diferença onze versus dez licenças permanece destacada, sem compra ou alteração de contrato.

## Prazos

| Sistema/local | Dúvida | Solicitação | BUG baixo / médio / alto / crítico | Melhoria |
|---|---|---|---|---|
| PGCP | 24h | 36h | 36h / 16h / 12h / 8h | Sem prazo determinado |
| PGLS | 24h | 168h | 168h / 120h / 24h / 6h | Sem prazo determinado |
| SISVISA | 24h | 168h | 168h / 120h / 24h / 8h | Sem prazo determinado |
| SIVISA+ Alagoinhas/Itabuna | 24h | 168h (7 dias) | 24h / 12h / 6h / 6h | Sem prazo determinado |
| SIVISA+ Maringá | 24h | 5 dias | 10 dias / 5 dias / 24h / 24h | Sem prazo determinado |

Persistir duração e unidade originais. Não converter cinco dias em quarenta horas úteis ou 120 horas corridas sem regra. A fonte oficial de calendário e cálculo de prazo remoto será o SLA/OLA configurado no GLPI. O administrador associa cada regra a um SLA válido, finalidade (resposta/solução), calendário e regras de pausa; publicar exige compatibilidade entre duração documental e objeto remoto. Um catálogo inacessível, SLA divergente ou regra sem calendário fica pendente, sem relogio local que finja substituir o GLPI. Sem prazo determinado não vira zero nem atraso imediato. Atrasado é indicador de prazo; fechamento com/sem sucesso conserva um resultado de negócio separado do status remoto.

## Entrega tipada ao GLPI

Estender o protocolo de efeitos de conversa com uma família própria Service Desk, preservando os comandos CRM existentes. A implementação pode usar um tipo de nó próprio ou uma nova variante discriminada, mas jamais enviar os campos GLPI arbitrários do navegador. A descoberta de capacidades só anuncia a operação quando o backend suporta a mesma revisão, o destino está vinculado e a conta está pronta. Os rótulos do editor devem explicar “Registrar demanda no Service Desk”, com resultado e caminhos de falha, não “Executar HTTP”.

Entrada: códigos publicados de sistema/local/perfil/motivo/submotivo/criticidade; identificação e contato; descrição; episódio e correlação da execução. Organização, conta, caixa, integração, conversa e conexão não podem ser escolhidas pelo texto do contato. Resolvem-se pela vinculação autenticada e são revalidadas imediatamente antes do envio. A associação contato/conversa deve ser do mesmo escopo, com revogação e revisão de controle preservadas. Respostas humanas/assunção interrompem ações futuras do robô conforme protocolo atual.

Backend JRC transforma os códigos em Destination e atributos permitidos, resolve solicitante e usa Glpi::AutomationCommand/Execute. O cadastro de solicitante externo exige política e direito específicos; não atribuir automaticamente o técnico como cliente só para completar o campo. Enquanto a identificação não estiver mapeada, permitir a triagem humana, sem divulgar chamados ao contato por mera coincidência de CPF/CNPJ ou telefone.

### Registro, atribuição e resultado

- Criar um episódio persistente de demanda, com UUID e revisão do catálogo. O UUID é gerado uma vez e reaproveitado em repetição, retomada e consulta de recibo. Atualizar Flow ou corrigir menu não pode, por si só, gerar outro ticket. “Nova demanda” explícita inicia outro episódio na mesma conversa.
- Os dois modos são configuração por caixa: após qualificação ou somente no pedido de humano. Ambos usam o mesmo episódio; no teste atual, o destino de comandos é exclusivamente o laboratório e a operação real permanece desabilitada.
- Guardar intenção, fingerprint e chave de idempotência antes de rede; o mesmo UUID com dados incompatíveis exige reconciliação/decisão, não nova criação silenciosa.
- Criação de Ticket, vínculo local e atribuição ao grupo/SLA podem ser etapas distintas. Cada uma tem recibo e estado. Após o Ticket criado, uma falha na atribuição é exibida como chamado criado com encaminhamento pendente; não repetir ticket.create para “consertar” grupo/SLA.
- Timeout após envio fica indeterminado. Consultar/reconciliar por correlação antes de qualquer reenvio. Reutilizar a referência remota para acompanhamentos e alterações tipadas.
- Confirmar sucesso pela origem. Resultado para o Flow inclui estado, protocolo confirmado quando houver, referência local e pendências; nunca tokens ou descrição privada. Só dizer “registrado e na fila” se ambas as etapas forem confirmadas.
- Associar GlpiReferenceLink e expor no Atendimento/Service Desk a triagem, número e estado do encaminhamento. Nenhuma cópia nativa editável de Ticket remoto é criada.

Auditoria: a operação automática registra ator de serviço JRC, organização, Flow/versão/execução, episódio e identidade técnica GLPI. A ação humana registra o operador que a iniciou. Não atribuir uma ação automática a um agente humano como se ele tivesse clicado. A identidade técnica GLPI continua sendo a aprovada; segredos cifrados ficam na conexão da conta.

## Acompanhamento, 48 horas e satisfação

Usar a API tipada do Service Desk para notas públicas/privadas, mudanças de estado, solução e encerramento. Mensagens e anexos obedecem às capacidades reais. Um print/vídeo recebido pode ficar no histórico JRC até haver envio seguro e autorizado ao GLPI; não prometer que foi anexado remotamente sem recibo.

Proposta de política para revisão: o relógio de 48 horas começa somente depois de uma solicitação explícita de informação pendente, com aviso confirmado entregue. Conta 48 horas corridas, independentemente do SLA do contrato. Resposta recebida cancela o encerramento; retorno humano, reclassificação ou cancelamento da solicitação invalidam o agendamento. Antes de agir, revalidar versão, estado remoto, resposta e regra ativa, serializando com o processamento da entrada. Recebimento mais recente prevalece sobre um job antigo.

Ao expirar, executar solução/fechamento permitido na origem, com resultado específico **encerrado por ausência de retorno**. Isso não significa sucesso técnico nem resolve o processo sanitário. Se faltarem permissões/transição/campos necessários, registrar pendência para operador, sem fechar apenas a projeção JRC. A proposta exige aprovação funcional antes de habilitar o fechamento real. O teste usa relógio virtual e GLPI isolado; não aguarda 48h nem fecha chamados reais.

Pesquisa: o texto e URL do documento são modelo. Publicar um único responsável pelo envio para evitar duplicar notificações GLPI/JRC/Broker. Condição proposta: conclusão confirmada de atendimento humano, uma avaliação por episódio, excluindo encerramento por falta de retorno e simples navegação de FAQ. Envio por WhatsApp depende das regras e capacidades do canal, inclusive janela/template; se indisponível, fica pendente ou é usado e-mail configurado, sem simular entrega. Nenhum disparo real nesta implantação de teste.

## Implantação e limites

É um projeto com três frentes dependentes: catálogo/regras JRC, protocolo Broker↔JRC e homologação da URA. Implementar em branches codex isoladas a partir das bases verificadas. Alterações do Broker exigem worktree sob diretório autorizado, pois o checkout de referência está fora das raízes graváveis. Não editar o Broker compartilhado nem publicar uma imagem global por conveniência. Recurso novo deve ser opt-in por organização/conta, com compatibilidade preservada para outros destinos.

Primeiro publicar o suporte compatível no JRC; depois no Broker; por último revisar/publicar o Flow apenas no canal de teste Branef. A descoberta de capacidades impede ativar um Flow dependente em backend antigo. A plataforma Broker é compartilhada: qualquer deploy adicional deverá identificar serviços afetados e preservar os demais canais; a solicitação atual autoriza a entrega Branef, não mudança nas regras de outros clientes.

Executar GLPI isolado com dados sintéticos para abertura/alteração/encerramento e notificações desabilitadas ou capturadas localmente. O número oficial, chamadas reais do GLPI, convites de usuários e avisos/satisfação reais continuam fora dessa homologação. Testes físicos no Welton usam apenas participantes de teste e mensagens esperadas. Não enviar a terceiros dados pessoais dos documentos.

Rollback: preservar Flow ativo anterior e revisão do catálogo; registrar digest antigo/novo das imagens. Reverter código/Flow não apaga Tickets já criados nem desfaz migrações destrutivamente. Jobs e comandos usam versão/estado, permitindo suspender novas entradas e reconciliar o que já foi despachado sem duplicar.

## Aceitação e prova de entrega

1. Quatro sistemas, locais, perfis e 65 submotivos presentes e rastreáveis às fontes, com exceções municipais e sem associação exclusiva inferida das linhas mescladas.
2. Todas as opções alcançáveis, caminhos de voltar/corrigir/falar com humano, validação dos dados e falhas de configuração exercitados no motor local e na UI; textos não contêm placeholders na publicação.
3. Dois modos de abertura testados; navegação/retomada/republish não duplicam ticket; nova demanda explícita permite outro protocolo.
4. Protocolo e capacidades Broker/JRC compatíveis; outro cliente, caixa, usuário, vínculo revogado e versão antiga não podem executar a entrega.
5. GLPI de laboratório comprova criação, vínculo, fila, SLA, acompanhamento, solução, fechamento e erro por permissão/transição. Falha parcial e timeout após escrita não geram falso sucesso nem repetição automática.
6. Datas Maringá/gerais, calendário, prazo sem definição, reclassificação e alteração de regra cobertos; nenhum indicador local simula uma atribuição de SLA remoto.
7. Política de 48h comprovada com relógio virtual, cancelamento por resposta/assunção, conflito com job e retorno antes/depois do limite. Sem testes em chamados reais.
8. Pesquisa e notificações têm destinatário, consentimento/capacidade do canal e uma origem de envio; efeitos em testes são capturados, não enviados.
9. Matriz de 11 pessoas conferida sem conceder Super Admin, enviar convites ou comprar licenças por automação; filas finais dependentes de IDs reais claramente identificadas.
10. Imagens por SHA/digest, deploy restrito, UI autenticada e teste físico controlado documentados separadamente dos testes sintéticos. Sem declarar “todos os fluxos em produção” enquanto houver mapeamento, permissão, calendário ou rota física pendente.

## Chamadas propostas que precisam ser visíveis na revisão

- A interpretação das dimensões mescladas como seleções independentes é proposta técnica, não informação explícita dos autores da planilha.
- A fila conjunta N2/N3 evita inventar uma divisão não documentada; o administrador poderá substituí-la por regra explícita.
- SLAs usam os valores detalhados já escolhidos pelo usuário, mas o cálculo depende do calendário/finalidade configurados no GLPI.
- Ambos os modos de abertura serão implementados; a habilitação real será configuração da caixa, preservando o teste sem escritas reais.
- A política de 48h corridas após aviso entregue, cancelamento por resposta e exclusão desse fechamento da pesquisa é proposta funcional, ainda não decisão anterior do usuário.

Após revisão e aprovação deste desenho: elaborar o plano de implementação, executar e testar; não é necessário pedir nova autorização para cada alteração reversível já coberta pelo escopo aprovado. Escritas reais, novos acessos sensíveis e efeitos externos excluídos acima continuam dependendo da definição específica correspondente.
