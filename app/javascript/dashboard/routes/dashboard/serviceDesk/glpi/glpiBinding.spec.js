import { afterEach, describe, expect, it, vi } from 'vitest';
import { createServiceDeskGlpiClient } from 'dashboard/api/serviceDeskGlpi';
import {
  glpiBinding,
  sameGlpiBinding,
  serviceDeskSourceChanged,
  commandMatchesBinding,
} from '../helpers/glpiBinding';
afterEach(() => vi.unstubAllGlobals());
describe('authenticated GLPI connection binding', () => {
  it('binds JSON, command and binary requests and exempts context/configuration handshakes', async () => {
    const http = {
      get: vi.fn(async () => ({})),
      post: vi.fn(async () => ({})),
      patch: vi.fn(async () => ({})),
    };
    vi.stubGlobal('axios', http);
    const client = createServiceDeskGlpiClient(() => ({
      connection_id: '9',
      connection_version: 0,
    }));
    const expected = {
      'X-JRC-GLPI-Connection-Id': '9',
      'X-JRC-GLPI-Connection-Version': '0',
    };
    await client.get('1', 'resources/tasks');
    expect(http.get.mock.calls.at(-1)[1].headers).toEqual(expected);
    await client.execute('1', { operation: 'ticket.update' });
    expect(http.post.mock.calls.at(-1)[2].headers).toEqual(expected);
    await client.downloadDocument('1', 20, 30);
    expect(http.get.mock.calls.at(-1)[1].headers).toEqual(expected);
    await client.downloadExport('1', 3);
    expect(http.get.mock.calls.at(-1)[1].headers).toEqual(expected);
    await client.get('1', 'context');
    expect(http.get.mock.calls.at(-1)[1].headers).toEqual({});
    await client.get('1', 'connection');
    expect(http.get.mock.calls.at(-1)[1].headers).toEqual({});
    await client.save('1', { enabled: false });
    expect(http.patch.mock.calls.at(-1)[2].headers).toBeUndefined();
  });
  it('requires paired canonical identifiers and a nonnegative connection revision', () => {
    expect(glpiBinding({ connection_id: 9, connection_version: 0 })).toEqual({
      connection_id: '9',
      connection_version: 0,
    });
    expect(() => glpiBinding({ connection_id: '9' })).toThrow();
    expect(() =>
      glpiBinding({ connection_id: '9', connection_version: -1 })
    ).toThrow();
    expect(
      sameGlpiBinding(
        { connection_id: '9', connection_version: 1 },
        { connection_id: '10', connection_version: 1 }
      )
    ).toBe(false);
  });
  it('redirects old references when primary source or its connection changes and preserves unrelated native routes', () => {
    const old = {
      data_source: 'glpi',
      connection_id: '9',
      connection_version: 1,
    };
    expect(
      serviceDeskSourceChanged(old, { ...old, connection_version: 2 })
    ).toBe(true);
    expect(serviceDeskSourceChanged(old, { data_source: 'native' })).toBe(true);
    expect(
      serviceDeskSourceChanged(
        { data_source: 'native', connection_id: '9', connection_version: 1 },
        { data_source: 'native', connection_id: '10', connection_version: 1 }
      )
    ).toBe(false);
    expect(
      commandMatchesBinding(
        { connection_id: '10', connection_version: 1 },
        glpiBinding(old)
      )
    ).toBe(false);
  });
});
