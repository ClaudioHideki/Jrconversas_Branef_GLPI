import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Blob as NodeBlob } from 'node:buffer';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import API from 'dashboard/api/serviceDeskGlpi';
import { useGlpi } from './useGlpi';

const holder = vi.hoisted(() => ({ session: null }));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/api/serviceDeskGlpi', () => ({ default: { get: vi.fn() } }));

const envelope = values => ({
  contract_version: 1,
  source: 'glpi',
  account_id: '1',
  user_id: '7',
  ...values,
});
const setup = () => {
  holder.session = {
    accountId: ref('1'),
    userId: ref('7'),
    state: reactive({ status: 'ready' }),
  };
  let glpi;
  const wrapper = mount({
    setup() {
      glpi = useGlpi();
      return () => null;
    },
  });
  return { glpi, wrapper };
};

beforeEach(() => vi.stubGlobal('Blob', NodeBlob));
afterEach(() => vi.unstubAllGlobals());

describe('GLPI request isolation', () => {
  it('discards a late response and clears data when authenticated account changes', async () => {
    let resolve;
    API.get.mockReturnValueOnce(
      new Promise(done => {
        resolve = done;
      })
    );
    const { glpi, wrapper } = setup();
    const read = glpi.read('context', 'context');
    holder.session.accountId.value = '2';
    resolve({ data: envelope({ available: true }) });
    expect(await read).toBeNull();
    expect(glpi.state.context).toBeNull();
    expect(glpi.state.data).toEqual({});
    wrapper.unmount();
  });
  it('keeps source 403 per resource visible when another request succeeds', async () => {
    API.get.mockRejectedValueOnce({
      response: { status: 403, data: { source_code: 'ERROR_RIGHT_MISSING' } },
    });
    API.get.mockResolvedValueOnce({ data: envelope({ items: [] }) });
    const { glpi, wrapper } = setup();
    await glpi.read('tasks', 'resources/tasks');
    await glpi.read('users', 'resources/users');
    await flushPromises();
    expect(glpi.state.errors.tasks).toEqual({
      status: 403,
      code: 'ERROR_RIGHT_MISSING',
    });
    expect(glpi.state.data.tasks).toBeUndefined();
    wrapper.unmount();
  });
  it('discards a late binary download after the authenticated user changes', async () => {
    let resolve;
    const { glpi, wrapper } = setup();
    const response = new Promise(done => {
      resolve = done;
    });
    const download = glpi.run('download', () => response, {
      binary: true,
      maxBytes: 1024,
    });
    holder.session.userId.value = '8';
    resolve({
      data: new Blob(['private'], { type: 'text/plain' }),
      status: 200,
    });
    expect(await download).toBeNull();
    expect(glpi.state.data).toEqual({});
    wrapper.unmount();
  });
  it('decodes an explicit source denial returned by a binary endpoint', async () => {
    const { glpi, wrapper } = setup();
    await glpi.run(
      'download',
      async () => {
        throw Object.assign(new Error('Source denied'), {
          response: {
            status: 403,
            data: new Blob(
              [JSON.stringify({ source_code: 'ERROR_RIGHT_MISSING' })],
              { type: 'application/json' }
            ),
          },
        });
      },
      { binary: true, maxBytes: 1024 }
    );
    expect(glpi.state.errors.download).toEqual({
      status: 403,
      code: 'ERROR_RIGHT_MISSING',
    });
    wrapper.unmount();
  });
  it('rejects a response for another authenticated user', async () => {
    API.get.mockResolvedValueOnce({
      data: envelope({ user_id: '99', items: [{ id: 1 }] }),
    });
    const { glpi, wrapper } = setup();
    expect(await glpi.read('tasks', 'resources/tasks')).toBeNull();
    expect(glpi.state.data.tasks).toBeUndefined();
    wrapper.unmount();
  });
});
