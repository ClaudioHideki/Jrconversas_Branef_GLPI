import { beforeEach, describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskGlpi';
import GlpiServiceDesk from './GlpiServiceDesk.vue';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';
import serviceMessages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
const holder = vi.hoisted(() => ({ session: null }));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/api/serviceDeskGlpi', () => {
  const api = { get: vi.fn() };
  return { default: api, createServiceDeskGlpiClient: () => api };
});
const envelope = data => ({
  data: {
    contract_version: 1,
    source: 'glpi',
    account_id: '1',
    user_id: '7',
    ...data,
  },
});
const globals = () => ({
  plugins: [
    createI18n({
      legacy: false,
      locale: 'en',
      messages: { en: { ...messages, ...serviceMessages } },
    }),
  ],
  stubs: {
    Button: {
      props: ['label', 'disabled'],
      template: '<button :disabled="disabled">{{ label }}</button>',
    },
    GlpiTicketWorkspace: {
      props: ['screen'],
      template: '<div data-testid="remote-tickets">{{ screen }}</div>',
    },
    GlpiOverview: { template: '<div data-testid="remote-overview" />' },
    GlpiResourceBoard: {
      props: ['resource'],
      template: '<div data-testid="remote-resource">{{ resource }}</div>',
    },
  },
});
beforeEach(() => {
  holder.session = {
    accountId: ref('1'),
    userId: ref('7'),
    state: reactive({ status: 'ready', context: { data_source: 'glpi' } }),
  };
  API.get.mockImplementation(async (_account, path) =>
    envelope(
      path === 'context'
        ? { available: true, entities: [] }
        : { operations: [] }
    )
  );
});

describe('GLPI operational workspace context', () => {
  it.each([
    ['overview', 'remote-overview'],
    ['tickets', 'remote-tickets'],
    ['mine', 'remote-tickets'],
    ['tasks', 'remote-resource'],
    ['approvals', 'remote-resource'],
    ['problems', 'remote-resource'],
    ['changes', 'remote-resource'],
    ['knowledge', 'remote-resource'],
    ['documents', 'remote-resource'],
    ['sla', 'remote-overview'],
    ['reports', 'remote-overview'],
  ])('uses the GLPI context for %s', async (screen, child) => {
    const wrapper = mount(GlpiServiceDesk, {
      props: { screen },
      global: globals(),
    });
    await flushPromises();
    expect(wrapper.find(`[data-testid="${child}"]`).exists()).toBe(true);
    expect(API.get.mock.calls.every(args => args[0] === '1')).toBe(true);
    wrapper.unmount();
  });
  it('keeps a disabled selected GLPI source unavailable without rendering native content', async () => {
    API.get.mockResolvedValue(envelope({ available: false, enabled: false }));
    const wrapper = mount(GlpiServiceDesk, {
      props: { screen: 'tickets' },
      global: globals(),
    });
    await flushPromises();
    expect(wrapper.text()).toContain(messages.JRC_GLPI.workspace.unavailable);
    expect(wrapper.find('[data-testid="remote-tickets"]').exists()).toBe(false);
    expect(API.get).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });
  it('shows a source 403 without an empty-list success state', async () => {
    API.get.mockRejectedValue({
      response: { status: 403, data: { source_code: 'ERROR_RIGHT_MISSING' } },
    });
    const wrapper = mount(GlpiServiceDesk, {
      props: { screen: 'tasks' },
      global: globals(),
    });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'ERROR_RIGHT_MISSING'
    );
    expect(wrapper.find('[data-testid="remote-resource"]').exists()).toBe(
      false
    );
    wrapper.unmount();
  });
});
