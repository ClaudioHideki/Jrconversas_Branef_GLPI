# Instalação Branef

Esta instalação usa aplicação, PostgreSQL, Redis e volumes exclusivos. O GLPI
continua no endereço do cliente. A integração consulta e cria chamados pela API v1.

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
7. Habilitar a integração e abrir Service Desk > Chamados GLPI.

Os tokens são cifrados e nunca retornam à tela após salvos. Para substituir um
token, preencher somente o campo correspondente. Campos vazios preservam valores
existentes. Validar de novo após trocar endpoint, credenciais ou permissões.

## Operação e falhas

- Lista, detalhe e relatórios consultam o GLPI; não criam cópias de Ticket nativo
  nem acionam os relógios e notificações do Service Desk local.
- Abertura grava um recibo antes do envio. Repetir a mesma referência não envia
  um segundo POST. Um timeout após o envio fica indeterminado, sem repetição automática.
- Consultar o resultado pelo formulário. Para reconciliar um resultado indeterminado,
  localizar o chamado pela marca `JRC: conta/envio`, depois informar número de envio
  e ID GLPI na configuração. O servidor confere conteúdo e entidade antes de vincular.
- 403 indica restrição de acesso; 404 não prova exclusão do histórico. Ajustar o
  perfil GLPI com o cliente. Anexos não integram esta primeira entrega; acompanhamentos
  e tarefas disponíveis são apresentados, com indicação de falha por coleção.
- Relatórios são limitados ao escopo autorizado, com máximo de 10.000 registros.
  O sistema detecta duplicação e mudança de contagem durante a coleta. Não apresenta
  ausência de prazo como cumprimento de SLA e não calcula gratificação.
- Usar filtros de abertura para separar períodos/legado. As regras financeiras e
  exclusões propostas no manual não são aplicadas automaticamente.

## Verificar e preservar

Conferir HTTPS, login, criação da conta/unidade, isolamento entre usuários, consulta
e abertura com identidade correta. Homologar uma abertura em ambiente apropriado e
confirmar o número no GLPI. A auditoria inicial usou somente GETs na origem.

Configurar backup do PostgreSQL, do volume `storage` e das chaves de criptografia.
Manter o digest anterior como referência de rollback. Antes de mudanças de schema,
preservar backup; rollback de imagem não desfaz migrations. Nenhum procedimento
desta documentação exige apagar volumes ou bancos.
