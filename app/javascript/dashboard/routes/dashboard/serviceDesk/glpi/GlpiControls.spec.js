import { afterEach, describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import Documents from './GlpiDocuments.vue';
import Sync from './GlpiSync.vue';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';
import serviceMessages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
const globalOptions = () => ({
  plugins: [
    createI18n({
      legacy: false,
      locale: 'en',
      messages: { en: { ...messages, ...serviceMessages } },
    }),
  ],
  stubs: {
    GlpiCoverage: true,
    Button: {
      props: ['label', 'disabled'],
      template: '<button :disabled="disabled">{{ label }}</button>',
    },
  },
});
afterEach(() => vi.useRealTimers());
describe('GLPI document and projection controls', () => {
  it('rejects uploads above 20MiB before any source command', async () => {
    const glpi = {
      state: reactive({
        loading: {},
        errors: {},
        data: {
          capabilities: {
            operations: [
              {
                operation: 'document.upload',
                supported: true,
                permitted: true,
                source_allowed: true,
              },
            ],
          },
        },
      }),
      run: vi.fn(),
    };
    const wrapper = mount(Documents, {
      props: { glpi, ticketId: 20 },
      global: globalOptions(),
    });
    const file = new File(['synthetic'], 'test.txt', { type: 'text/plain' });
    Object.defineProperty(file, 'size', { value: 20 * 1024 * 1024 + 1 });
    Object.defineProperty(wrapper.get('input[type="file"]').element, 'files', {
      value: [file],
      configurable: true,
    });
    await wrapper.get('input[type="file"]').trigger('change');
    await wrapper.get('form').trigger('submit');
    expect(wrapper.get('[role="alert"]').text()).toContain(
      messages.JRC_GLPI.workspace.upload_limit
    );
    expect(glpi.run).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('requires a ticket relationship before downloading a document', async () => {
    const glpi = {
      state: reactive({ loading: {}, errors: {}, data: {} }),
      run: vi.fn(),
    };
    const wrapper = mount(Documents, {
      props: {
        glpi,
        items: [{ id: 2, documents_id: 17, filename: 'private.pdf' }],
      },
      global: globalOptions(),
    });
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();
    expect(wrapper.find('form').exists()).toBe(false);
    expect(glpi.run).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('polls the newly returned sync id and stops when unmounted', async () => {
    vi.useFakeTimers();
    const state = reactive({
      loading: {},
      data: { sync: { sync: { id: 'old', state: 'complete' } } },
    });
    const read = vi.fn(async (_key, path) => ({
      sync: {
        id: path === 'sync' ? 'old' : 'new',
        state: path === 'sync' ? 'complete' : 'running',
        coverage: {},
      },
    }));
    const startSync = vi.fn(async () => ({
      sync: { id: 'new', state: 'running' },
    }));
    const run = async (_key, action) => {
      const result = await action('1');
      state.data.sync = result;
      return result;
    };
    const wrapper = mount(Sync, {
      props: { glpi: { state, read, run, API: { startSync } } },
      global: globalOptions(),
    });
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    await vi.advanceTimersByTimeAsync(2000);
    expect(read).toHaveBeenCalledWith('sync', 'sync/new');
    expect(read).not.toHaveBeenCalledWith('sync', 'sync/old');
    wrapper.unmount();
    const count = read.mock.calls.length;
    await vi.advanceTimersByTimeAsync(10000);
    expect(read).toHaveBeenCalledTimes(count);
  });
});
