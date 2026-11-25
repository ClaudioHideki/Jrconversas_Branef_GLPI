# Análise do chamado selecionado e relatório por número

- Status: Aceita
- Data: 2026-11-24

A seleção de um chamado analisa seus textos públicos disponíveis sem solicitar novamente um período. Datas na lista continuam sendo filtros de localização. O contrato scope=ticket é mutuamente exclusivo com from/to; a consulta por período permanece compatível para análises históricas existentes.

A inferência usa o provedor da conta, inclusive Anthropic nativo, com recibos reais no mesmo controle de consumo. Mantêm-se autorização por conta, unidade e chamado, releitura de permissões, exclusão de notas privadas e limites de 100 registros/1000 caracteres por registro, explicitados na cobertura. Isso é inferência textual, não pesquisa respondida pelo cliente nem escuta de áudio.

A tela permite abrir o chamado no JRC e selecionar vários chamados da página para análise sequencial, sem retry automático. Uma troca de escopo descarta respostas atrasadas. O relatório HTML/CSV reúne cada número, estado da análise, resumo, sentimentos, evidências, modelo, cobertura e tokens confirmados. Os resultados ficam na tela e no arquivo exportado; não alteram registros do GLPI.

Testes cobrem o contrato sem datas, exclusão de notas privadas, abertura do chamado, execução sequencial, isolamento de resposta atrasada e escape de HTML/fórmulas de planilha. CI do SHA final, imagem e conferência autenticada são gates separados.

Na validação produtiva, o Rack interrompeu a inferência aos 15 segundos. Apenas o POST exato de análise recebe orçamento de 100 segundos, superior ao limite de 75 segundos do cliente de inferência e inferior aos 120 segundos da interface. As outras rotas mantêm a configuração original, com instâncias separadas para evitar alteração concorrente do timeout. Tentativas interrompidas continuam incertas no controle de consumo; não são apresentadas como zero nem repetidas automaticamente.

## Detalhe e relatório geral — 25/11/2026

O resultado usa quatro seções: resumo, nota e cobertura, pontos de atenção e evidências do GLPI. Os rótulos de sentimento do cliente e do atendente aparecem separadamente. A nota vem do resultado textual já entregue pela IA, com ausência de evidência representada explicitamente. A seção de evidências mostra referências aos registros públicos e observações da análise. Critérios e pesos da monitoria de áudio ficam fora deste contrato.

O relatório geral da sessão reúne os resultados por chamado. A lista e o HTML distinguem análises concluídas, ausência de texto e falhas. A exportação CSV mantém uma linha por chamado. Para cobrir todos os resultados de um intervalo, o próximo incremento precisa persistir um lote com os IDs autorizados do filtro, acompanhar o processamento em segundo plano e registrar o resultado por chamado. O trabalho atual continua usando a seleção da página.

## Lote persistente de todas as páginas — 25/11/2026

O lote congela os IDs, entidades e o horário de corte no servidor. Exige coleta completa para o filtro e acesso já concedido a todos os chamados das unidades do operador. O processamento usa apenas descrições, acompanhamentos públicos e soluções no período, com a mesma inferência e os mesmos recibos de consumo da análise individual. Sem datas, considera o histórico do chamado até a criação do lote.

Uma conexão GLPI executa um lote ativo por vez. A execução fica no Sidekiq e mantém contadores distintos para fila, execução, conclusão, falta de texto, falha e cancelamento. O cancelamento encerra a fila após o item em andamento. Após interrupção do worker, itens com execução incerta ficam registrados como falha para evitar repetir inferências cobradas. O relatório geral usa a projeção autorizada e a análise detalhada exige revalidação do chamado e de sua versão no GLPI.
