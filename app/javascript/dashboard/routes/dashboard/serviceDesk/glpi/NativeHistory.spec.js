import { beforeEach, describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDesk';
import NativeHistory from './NativeHistory.vue';
import {
  contextPayload,
  identity,
  collection,
  ticket,
  detail,
} from '../__tests__/fixtures';
import { decodeContext } from '../helpers/contracts';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';
import serviceMessages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
const holder = vi.hoisted(() => ({ session: null }));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/api/serviceDesk', () => ({
  default: { list: vi.fn(), ticket: vi.fn() },
}));
const globals = () => ({
  plugins: [
    createI18n({
      legacy: false,
      locale: 'en',
      messages: { en: { ...messages, ...serviceMessages } },
    }),
  ],
  stubs: {
    Button: { props: ['label'], template: '<button>{{ label }}</button>' },
  },
});
beforeEach(() => {
  holder.session = {
    accountId: ref('1'),
    userId: ref('7'),
    state: reactive({
      status: 'ready',
      context: decodeContext(contextPayload({ data_source: 'glpi' }), identity),
    }),
  };
  API.list.mockResolvedValue(
    collection([ticket()], { meta: { page: 1, per_page: 20, total: 1 } })
  );
  API.ticket.mockResolvedValue(detail(ticket()));
});
describe('preserved JRC native history', () => {
  it('opens only local records returned by the local list and exposes no mutation control', async () => {
    const wrapper = mount(NativeHistory, { global: globals() });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(row => row.text().includes('TEST-20'))
      .trigger('click');
    await flushPromises();
    expect(API.ticket.mock.calls[0].slice(0, 2)).toEqual(['1', '20']);
    expect(wrapper.text()).toContain(
      messages.JRC_GLPI.workspace.native_history_help
    );
    expect(wrapper.find('input, textarea, select, a').exists()).toBe(false);
    expect(wrapper.findAll('button')).toHaveLength(1);
    wrapper.unmount();
  });
  it('discards a local detail returned after the authenticated account changes', async () => {
    let resolve;
    API.ticket.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = mount(NativeHistory, { global: globals() });
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(row => row.text().includes('TEST-20'))
      .trigger('click');
    holder.session.state.status = 'loading';
    holder.session.accountId.value = '2';
    resolve(detail(ticket({ description: 'Private native detail' })));
    await flushPromises();
    expect(wrapper.text()).not.toContain('Private native detail');
    wrapper.unmount();
  });
});
