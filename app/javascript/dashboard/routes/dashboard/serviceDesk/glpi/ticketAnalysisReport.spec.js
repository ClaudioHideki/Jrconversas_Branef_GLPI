import { describe, it, expect } from 'vitest';
import { analysisReportHtml, analysisReportCsv } from './ticketAnalysisReport';
const row = {
  ticket_id: 12,
  title: '<img src=x onerror=alert(1)>',
  status: 'analyzed',
  model: 'account-model',
  analyzed_at: '2026-11-24',
  usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15 },
  source_window: {
    analyzed_records: 2,
    omitted_records: 0,
    truncated_records: 1,
  },
  report: {
    summary: '=SUM(1)',
    customer_sentiment: 'neutral',
    agent_sentiment: 'insufficient_data',
    quality_score: null,
    risks: [],
    recommendations: [],
    evidence: [
      { message_id: 'Ticket/12', observation: '<script>bad()</script>' },
    ],
    limitations: 'Texto reduzido',
  },
};
describe('human-readable per-ticket reports', () => {
  it('preserves ticket numbers, real receipts and coverage while escaping untrusted HTML', () => {
    const html = analysisReportHtml(
      [row, { ticket_id: 3, status: 'no_public_text' }],
      '2026-11-24'
    );
    expect(html.indexOf('Chamado #3')).toBeLessThan(
      html.indexOf('Chamado #12')
    );
    expect(html).toContain('total: 15');
    expect(html).toContain('1 reduzidos');
    expect(html).toContain('Ticket/12');
    expect(html).not.toContain('<script>');
    expect(html).not.toContain('<img');
    expect(html).toContain('&lt;script&gt;');
  });
  it('exports one row per actual result and neutralizes spreadsheet formulas', () => {
    const csv = analysisReportCsv([
      row,
      { ticket_id: 4, status: 'failed', error: 'provider_unavailable' },
    ]);
    expect(csv).toContain('provider_unavailable');
    expect(csv).toContain("'=SUM(1)");
    expect(csv).toContain('15');
    expect(csv.split('\r\n')).toHaveLength(3);
    expect(csv).not.toContain('estimado');
  });
});
