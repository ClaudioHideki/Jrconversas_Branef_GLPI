# Branef: conversas abertas e pendentes no Atendimento

## Objetivo e decisão

Mostrar na lista lateral de Atendimento as conversas abertas e pendentes acessíveis ao usuário, identificando seu estado. O usuário escolheu essa apresentação conjunta em 06/11/2026. A alternativa considerada foi um filtro separado para pendentes, que exigiria alternar a consulta para acompanhar o robô.

## Evidência do problema

A URA de teste está publicada no Broker, automação `5a31d9e5-d033-430f-8cc7-f482ae2c8241`, versão 1, vinculada ao canal Welton e à conta Branef 3, caixa API 1. A conversa 1 tem entradas reais, respostas da URA entregues no WhatsApp e histórico espelhado no JRC. A retomada do bot coloca a conversa como pendente. `InboxList.vue` consulta e seleciona apenas `open`; por isso a conversa deixa de aparecer na lista lateral.

## Comportamento proposto

- A lista consulta abertos e pendentes em conjunto, ordenados pela última atividade, com paginação e contagem referentes ao conjunto autorizado. Resolvidos e adiados permanecem fora.
- Cada item identifica o estado, usando os textos já existentes para aberto e pendente. Pendente não será apresentado como prova de que há um robô ativo.
- Os filtros de responsável e canal continuam aplicáveis. Minhas exige atribuição ao usuário; administradores usam Todas para acompanhar também conversas sem agente atribuído.
- Abrir uma conversa para leitura não altera seu status, atribuição nem controle do bot. Assumir, responder, resolver e retomar continuam ações explícitas do fluxo existente.
- Mudanças em tempo real devem incluir a transição aberto/pendente e remover os resolvidos sem duplicar itens.
- Não se altera o enum de status persistido. O mecanismo de consulta conjunta será escolhido conforme as interfaces existentes; se necessário, um parâmetro de consulta específico limitará os estados no servidor, preservando consultas legadas.

## Escopo e validação

Implementar na base Branef existente, em branch isolada. Validar consulta e paginação, responsável/canal, isolamento de conta e caixa, transições em tempo real e ausência de escrita ao visualizar. Publicar imagem imutável após os testes e implantar somente na Branef, preservando ENV, segredos, banco, Redis, S3, NICO e integração GLPI. Conferir visualmente a conversa de teste na lista e o bot respondendo após simples visualização.

A URA de teste permanece sem operações GLPI. Essa mudança não habilita produção do robô, não cria chamados, não modifica equipes nem amplia permissões dos agentes.

## Aprovação

A apresentação conjunta e este desenho foram aprovados pelo usuário em 06/11/2026, incluindo implementação, testes, publicação da imagem e implantação somente na Branef.
