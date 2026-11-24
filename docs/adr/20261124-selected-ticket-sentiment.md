# Análise do chamado selecionado e relatório por número

- Status: Aceita
- Data: 2026-11-24

A seleção de um chamado analisa seus textos públicos disponíveis sem solicitar novamente um período. Datas na lista continuam sendo filtros de localização. O contrato scope=ticket é mutuamente exclusivo com from/to; a consulta por período permanece compatível para análises históricas existentes.

A inferência usa o provedor da conta, inclusive Anthropic nativo, com recibos reais no mesmo controle de consumo. Mantêm-se autorização por conta, unidade e chamado, releitura de permissões, exclusão de notas privadas e limites de 100 registros/1000 caracteres por registro, explicitados na cobertura. Isso é inferência textual, não pesquisa respondida pelo cliente nem escuta de áudio.

A tela permite abrir o chamado no JRC e selecionar vários chamados da página para análise sequencial, sem retry automático. Uma troca de escopo descarta respostas atrasadas. O relatório HTML/CSV reúne cada número, estado da análise, resumo, sentimentos, evidências, modelo, cobertura e tokens confirmados. Os resultados ficam na tela e no arquivo exportado; não alteram registros do GLPI.

Testes cobrem o contrato sem datas, exclusão de notas privadas, abertura do chamado, execução sequencial, isolamento de resposta atrasada e escape de HTML/fórmulas de planilha. CI do SHA final, imagem e conferência autenticada são gates separados.

Na validação produtiva, o Rack interrompeu a inferência aos 15 segundos. Apenas o POST exato de análise recebe orçamento de 100 segundos, superior ao limite de 75 segundos do cliente de inferência e inferior aos 120 segundos da interface. As outras rotas mantêm a configuração original, com instâncias separadas para evitar alteração concorrente do timeout. Tentativas interrompidas continuam incertas no controle de consumo; não são apresentadas como zero nem repetidas automaticamente.
