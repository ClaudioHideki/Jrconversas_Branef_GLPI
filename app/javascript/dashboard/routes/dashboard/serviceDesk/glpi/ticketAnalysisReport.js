const escape = value =>
  String(value ?? '').replace(
    /[&<>"']/g,
    ch =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[
        ch
      ]
  );
const labels = {
  positive: 'Positivo',
  neutral: 'Neutro',
  negative: 'Negativo',
  mixed: 'Misto',
  insufficient_data: 'Evidência insuficiente',
};
const label = value => labels[value] || 'Evidência insuficiente';
export function analysisReportHtml(
  entries,
  generatedAt = new Date().toISOString()
) {
  const sections = [...entries]
    .sort((a, b) => Number(a.ticket_id) - Number(b.ticket_id))
    .map(row => {
      const r = row.report;
      const w = row.source_window;
      const u = row.usage;
      return (
        '<section><h2>Chamado #' +
        escape(row.ticket_id) +
        ' · ' +
        escape(row.title || '') +
        '</h2>' +
        (!r
          ? '<p>' +
            escape(
              row.status === 'no_public_text'
                ? 'Sem texto público para análise.'
                : 'Análise não concluída: ' + (row.error || row.status)
            ) +
            '</p>'
          : '<p>' +
            escape(r.summary) +
            '</p><dl><dt>Cliente</dt><dd>' +
            label(r.customer_sentiment) +
            '</dd><dt>Atendente</dt><dd>' +
            label(r.agent_sentiment) +
            '</dd><dt>Qualidade</dt><dd>' +
            escape(r.quality_score ?? 'Evidência insuficiente') +
            '</dd><dt>Modelo</dt><dd>' +
            escape(row.model) +
            '</dd><dt>Analisado em</dt><dd>' +
            escape(row.analyzed_at) +
            '</dd><dt>Cobertura</dt><dd>' +
            escape(w?.analyzed_records) +
            ' registros; ' +
            escape(w?.omitted_records) +
            ' omitidos; ' +
            escape(w?.truncated_records) +
            ' reduzidos.</dd><dt>Tokens confirmados</dt><dd>Entrada: ' +
            escape(u?.input_tokens) +
            '; saída: ' +
            escape(u?.output_tokens) +
            '; total: ' +
            escape(u?.total_tokens) +
            '</dd></dl>' +
            ['risks', 'recommendations']
              .map(
                (key, i) =>
                  '<h3>' +
                  ['Riscos', 'Recomendações'][i] +
                  '</h3><ul>' +
                  (r[key] || [])
                    .map(x => '<li>' + escape(x) + '</li>')
                    .join('') +
                  '</ul>'
              )
              .join('') +
            '<h3>Evidências GLPI</h3><ul>' +
            (r.evidence || [])
              .map(
                x =>
                  '<li>' +
                  escape(x.message_id) +
                  ': ' +
                  escape(x.observation) +
                  '</li>'
              )
              .join('') +
            '</ul><p>' +
            escape(r.limitations) +
            '</p>') +
        '</section>'
      );
    })
    .join('');
  return (
    '<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src &#39;none&#39;; style-src &#39;unsafe-inline&#39;; img-src &#39;none&#39;"><title>Análise dos chamados</title><style>body{font:15px Arial,sans-serif;max-width:1000px;margin:32px auto;color:#16243b;line-height:1.5;padding:0 20px}section{border-top:1px solid #ccd5e0;margin-top:24px;padding-top:12px;break-inside:avoid}dl{display:grid;grid-template-columns:180px 1fr;gap:6px}dd{margin:0}p,li{white-space:pre-wrap;overflow-wrap:anywhere}@media print{body{margin:0;max-width:none}}</style><h1>Análise de sentimento dos chamados</h1><p>Gerado em ' +
    escape(generatedAt) +
    '. ' +
    entries.length +
    ' chamado(s).</p><p>Análise inferida dos textos públicos disponíveis. Não equivale a uma pesquisa respondida pelo cliente. Áudio, anexos e notas privadas não são analisados. A cobertura e os tokens são apresentados por chamado.</p>' +
    sections +
    '</html>'
  );
}
export function analysisReportCsv(entries) {
  const cell = value => {
    let text = String(value ?? '');
    if (/^[=+@\-\t\r]/.test(text)) text = "'" + text;
    return '"' + text.replaceAll('"', '""') + '"';
  };
  const headers = [
    'Chamado',
    'Título',
    'Resultado',
    'Sentimento cliente',
    'Sentimento atendente',
    'Qualidade',
    'Resumo',
    'Modelo',
    'Analisado em',
    'Registros analisados',
    'Registros omitidos',
    'Textos reduzidos',
    'Tokens entrada',
    'Tokens saída',
    'Tokens total',
  ];
  return (
    '\uFEFF' +
    [
      headers,
      ...[...entries]
        .sort((a, b) => Number(a.ticket_id) - Number(b.ticket_id))
        .map(x => [
          x.ticket_id,
          x.title,
          x.status,
          x.report ? label(x.report.customer_sentiment) : '',
          x.report ? label(x.report.agent_sentiment) : '',
          x.report?.quality_score,
          x.report?.summary || x.error,
          x.model,
          x.analyzed_at,
          x.source_window?.analyzed_records,
          x.source_window?.omitted_records,
          x.source_window?.truncated_records,
          x.usage?.input_tokens,
          x.usage?.output_tokens,
          x.usage?.total_tokens,
        ]),
    ]
      .map(row => row.map(cell).join(';'))
      .join('\r\n')
  );
}
