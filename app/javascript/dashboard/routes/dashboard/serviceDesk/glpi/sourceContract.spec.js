import { describe, it, expect } from 'vitest';
import { decodeContext } from '../helpers/contracts';

const identity = { accountId: '3', userId: '2' };
const payload = {
  contract_version: 1,
  account_id: '3',
  user_id: '2',
  available: true,
  units: [],
  capabilities: {},
};

describe('Service Desk account data source contract', () => {
  it('preserves native as the default and selects an explicit GLPI source', () => {
    expect(decodeContext(payload, identity).data_source).toBe('native');
    expect(
      decodeContext({ ...payload, data_source: 'glpi' }, identity).data_source
    ).toBe('glpi');
  });

  it('rejects a foreign account and an unsupported source', () => {
    expect(() =>
      decodeContext({ ...payload, account_id: '4' }, identity)
    ).toThrow();
    expect(() =>
      decodeContext({ ...payload, data_source: 'proxy' }, identity)
    ).toThrow();
  });
});
