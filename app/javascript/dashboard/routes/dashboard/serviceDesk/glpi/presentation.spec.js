import {
  formatGlpiDate,
  plainText,
  groupErrors,
  selectedFilters,
} from './presentation';

describe('GLPI display without changing source semantics', () => {
  it('interprets naive timestamps in the configured GLPI timezone and offset timestamps as instants', () => {
    expect(formatGlpiDate('2026-11-13 10:30:00', 'America/Sao_Paulo')).toBe(
      '13/11/2026, 10:30'
    );
    expect(formatGlpiDate('2026-11-13T13:30:00Z', 'America/Sao_Paulo')).toBe(
      '13/11/2026, 10:30'
    );
    expect(formatGlpiDate('2026-11-13 10:30:00')).toBe('2026-11-13 10:30:00');
  });
  it('decodes entity labels as plain text and does not turn remote markup into executable elements', () => {
    expect(plainText('BRANEF &gt; SUPORTE &gt; SISVISA')).toBe(
      'BRANEF > SUPORTE > SISVISA'
    );
    expect(plainText('&lt;img src=x onerror=alert(1)&gt;')).toBe(
      '<img src=x onerror=alert(1)>'
    );
  });
  it('groups repeated errors but retains each affected operation', () => {
    expect(
      groupErrors({
        sla: { code: 'ERROR_RIGHT_MISSING' },
        calendars: { code: 'ERROR_RIGHT_MISSING' },
        tickets: { code: 'forbidden' },
      })
    ).toEqual([
      { code: 'ERROR_RIGHT_MISSING', operations: ['sla', 'calendars'] },
      { code: 'forbidden', operations: ['tickets'] },
    ]);
  });
  it('accepts only scalar supported list filters from a route', () => {
    expect(
      selectedFilters({
        from: '2026-11-01',
        status: '4',
        search: ['one', 'two'],
        admin: 'true',
        mine: true,
      })
    ).toEqual({ from: '2026-11-01', status: '4' });
  });
});
