import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import Overview from './GlpiOverview.vue';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';
import serviceMessages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
beforeEach(() => vi.useFakeTimers());
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});
describe('GLPI export delivery', () => {
  it('starts verification from ready without proof then polls before one authenticated download', async () => {
    const state = reactive({
      context: { entities: [], can_export: true },
      loading: {},
      errors: {},
      data: {
        export: {
          export: {
            id: '9',
            state: 'ready',
            processed: 2,
            total: 2,
            can_download: false,
          },
        },
      },
    });
    const downloadExport = vi.fn();
    const read = vi.fn(async (_key, path) => {
      if (path === 'exports/9')
        state.data.export.export = {
          id: '9',
          state: 'ready',
          processed: 2,
          total: 2,
          can_download: true,
        };
    });
    const run = vi.fn(async (_key, action) => {
      await action('1', new AbortController().signal);
      if (downloadExport.mock.calls.length === 1) {
        state.data.export.export = {
          id: '9',
          state: 'verifying',
          processed: 2,
          total: 2,
        };
        return state.data.export;
      }
      return { binary: new Blob(['safe csv'], { type: 'text/csv' }) };
    });
    const BaseURL = URL;
    const objectUrl = vi.fn(() => 'blob:test-export');
    const revoke = vi.fn();
    vi.stubGlobal(
      'URL',
      class extends BaseURL {
        static createObjectURL = objectUrl;

        static revokeObjectURL = revoke;
      }
    );
    const click = vi
      .spyOn(HTMLAnchorElement.prototype, 'click')
      .mockImplementation(() => {});
    const wrapper = mount(Overview, {
      props: { glpi: { state, read, run, API: { downloadExport } } },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en: { ...messages, ...serviceMessages } },
          }),
        ],
        stubs: {
          GlpiFilters: true,
          GlpiCoverage: true,
          Button: {
            props: ['label', 'disabled'],
            template: '<button :disabled="disabled">{{ label }}</button>',
          },
        },
      },
    });
    const button = wrapper
      .findAll('button')
      .find(item => item.text() === messages.JRC_GLPI.workspace.download);
    expect(button.attributes('disabled')).toBeUndefined();
    await button.trigger('click');
    await flushPromises();
    expect(downloadExport).toHaveBeenCalledTimes(1);
    expect(click).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(2000);
    await flushPromises();
    expect(downloadExport).toHaveBeenCalledTimes(2);
    expect(click).toHaveBeenCalledTimes(1);
    wrapper.unmount();
    click.mockRestore();
  });
});
