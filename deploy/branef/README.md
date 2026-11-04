# Instalação Branef

Esta instalação usa aplicação, PostgreSQL, Redis e volumes exclusivos. O GLPI
continua no endereço do cliente. A integração usa a API REST v1; os comandos
disponíveis dependem das permissões atuais do operador JRC e do perfil GLPI.

Este guia descreve a configuração da revisão em desenvolvimento. A publicação de
uma branch ou um teste aprovado não comprova sua implantação. O relatório da
entrega deve registrar separadamente imagem publicada, revisão em execução,
laboratório e homologação no GLPI do cliente.

## Preparar o projeto no Dokploy

1. Criar um projeto Compose exclusivo para a Branef e conectar este repositório
   na revisão publicada. Selecionar `deploy/branef/compose.yaml` como arquivo.
2. Preencher as variáveis de `branef.env.example` no ambiente do projeto. O domínio
   deve apontar para o servidor Dokploy; confirmar que o servidor usa a rede
   `dokploy-network`, o entrypoint `websecure` e o resolver `letsencrypt`.
   Se a instalação Dokploy usa outros nomes, adaptar somente essas referências.
3. Usar em `JRC_IMAGE` o digest verificado da imagem Branef. O mesmo valor será
   usado por Rails, Sidekiq e preparação. Não apontar para uma imagem antiga sem
   o conector. O pacote da imagem deve estar acessível ao servidor.
4. Gerar segredos independentes com `openssl rand -hex 64` para SECRET_KEY_BASE e
   `openssl rand -hex 32` para cada uma das outras chaves e senhas. Guardar essas
   chaves junto com o plano de backup. Não reutilizar credenciais da instalação JRC.
5. Configurar SMTP para recuperação de senha e convites. O arquivo de exemplo não
   contém credenciais prontas. As credenciais GLPI serão cadastradas na interface.
6. Implantar. `prepare` aplica o schema/migrations antes de Rails e Sidekiq. Não
   há portas de banco ou Redis publicadas. Banco, Redis e arquivos têm volumes
   independentes; sua persistência não depende do ciclo de vida dos containers.

## Criar a conta e inicializar o Service Desk

Concluir o onboarding nativo da instalação e criar a conta Branef com seu
administrador cliente confirmado. Habilitar `jrc_service_desk` na conta.
A estrutura inicial do Service Desk usa o fluxo nativo de inicialização do
Super Admin: cadastrar o ID nominativo do operador autorizado em
`JRC_SERVICE_DESK_INITIALIZER_USER_IDS` e usar a ação de inicialização na conta,
selecionando o administrador cliente, a empresa operadora e a unidade Branef.
O operador de implantação e o administrador cliente são identidades distintas.
O comando de preparação do banco não cria automaticamente concessões operacionais.

## Configurar o GLPI

1. Entrar como administrador da conta e abrir Service Desk > Integração GLPI.
2. Salvar a URL HTTPS terminada em `/apirest.php`, User Token, App Token e o fuso
   das datas da origem. Manter a integração desabilitada durante a configuração.
3. Testar a conexão. A resposta informa perfil, entidades e direitos anunciados.
4. Vincular somente as entidades autorizadas às unidades do Service Desk. A raiz
   GLPI tem ID 0, que é válido. Um vínculo por entidade não concede acesso recursivo
   a entidades não vinculadas. Salvar os vínculos.
5. Vincular os agentes a seus IDs GLPI. Sem esse vínculo, agentes não recebem
   chamados externos. Agentes vinculados veem registros em que são solicitantes ou
   técnicos, dentro das unidades autorizadas. Restrições nativas de supervisão por
   fila não são ampliadas: unidades com essas restrições ficam fora do conector
   até que exista mapeamento equivalente. Administradores também respeitam entidades
   vinculadas e as permissões do token GLPI.
6. Se a origem exigir categoria, cadastrar categorias permitidas com referências
   validadas: `[{"id":123,"name":"Suporte","entity_id":1}]`. Não confundir IDs GLPI
   com IDs locais. O perfil do manual retornou 403 nos catálogos durante a auditoria;
   ajustar permissões específicas ou obter os IDs com a administração GLPI.
7. Habilitar a integração. Para usar o GLPI nas telas operacionais do Service Desk,
   selecionar `primary_source` na configuração autenticada da conta. Essa opção
   fica no banco da aplicação; não é uma URL adicional no ENV nem uma opção do navegador.
   Com a fonte GLPI selecionada, desabilitar a conexão apresenta indisponibilidade;
   não faz as telas retornarem silenciosamente aos chamados locais.
8. Iniciar a coleta administrativa dos chamados. Acompanhar o recibo e a cobertura
   por entidade. Os indicadores e a lista principal usam essa projeção de leitura;
   detalhes e operações verificam a origem. Uma coleta parcial não comprova que
   todos os chamados foram disponibilizados.

Os tokens são cifrados e nunca retornam à tela após salvos. Para substituir um
token, preencher somente o campo correspondente. Campos vazios preservam valores
existentes. Validar de novo após trocar endpoint, credenciais ou permissões.

## Operação e falhas

- Lista, indicadores e relatórios compartilham filtros e uma projeção derivada,
  identificada pela conexão, versão e horário da coleta. Não existem cópias
  editáveis de Ticket nativo para cada chamado GLPI. A coleta informa falhas de
  busca, detalhe, entidade ou atores; uma falha não se transforma em total zero.
- Criação, edição e demais operações registram intenção durável antes do envio,
  identidade técnica GLPI e operador JRC. Repetir a mesma chave com os mesmos
  dados recupera o recibo. Um timeout após o envio fica indeterminado, sem
  repetição automática. O recibo só confirma sucesso depois da verificação na origem.
- Consultar o resultado pelo formulário. Para reconciliar um resultado indeterminado,
  localizar o chamado pela marca `JRC: conta/envio`, depois informar número de envio
  e ID GLPI na configuração. O servidor confere conteúdo e entidade antes de vincular.
- 403 indica restrição de acesso; 404 não prova exclusão do histórico. Ajustar o
  perfil GLPI com o cliente. O manifesto separa suporte do conector, permissão
  local, direito anunciado pelo perfil e homologação. Um direito de perfil não
  substitui a autorização por registro na origem.
- Anexos usam o backend autenticado: envio até 20 MiB, download até 50 MiB, podendo
  haver limites menores no GLPI. Upload e associação possuem etapas distintas.
  Retirar o vínculo não exclui o arquivo compartilhado. Não publicar URLs com tokens.
- Exportações são tarefas em segundo plano, sem corte silencioso em 10.000 linhas.
  Exigem cobertura completa do escopo solicitado e nova verificação antes do
  download. O arquivo é privado, expira em 24 horas e possui limite operacional
  padrão de 100 MiB (`GLPI_EXPORT_MAX_BYTES`, em bytes, opcional). Exceder o limite
  produz falha explícita; não entrega um CSV truncado. A janela de verificação
  não representa um snapshot transacional do GLPI.
- Chamados locais anteriores permanecem no histórico JRC. Não converter, apagar
  ou enviar esses registros ao GLPI automaticamente. Não aplicar relógios locais
  nem duplicar notificações GLPI em uma referência remota.
- Datas e prazos vêm da origem. Ausência de prazo não conta como cumprimento de
  SLA. Não calcular gratificações a partir de regras propostas em um manual.
- Usar filtros de abertura para separar períodos/legado. As regras financeiras e
  exclusões propostas no manual não são aplicadas automaticamente.

## Verificar e preservar

Conferir HTTPS, login, criação da conta/unidade, isolamento entre usuários, consulta
e abertura com identidade correta. Homologar uma abertura em ambiente apropriado e
confirmar o número no GLPI. A auditoria inicial usou somente GETs na origem.

Preservar os mecanismos de backup já configurados e as chaves de criptografia.
Manter o digest anterior como referência de rollback: voltar a imagem não desfaz
migrations. A implantação desta revisão não exige apagar volumes, recriar banco,
redefinir senhas nem gerar um novo backup manual.

As credenciais GLPI ficam cifradas por conta no banco e são cadastradas pela tela
administrativa. Senhas do PostgreSQL/Redis, chaves Rails, SMTP, S3 e token NICO
continuam no Environment do Compose. Não colocar segredos no Git, neste guia ou
no relatório de implantação. Todos os processos da aplicação devem conservar as
mesmas chaves Rails; trocá-las pode tornar os tokens já cifrados ilegíveis.
