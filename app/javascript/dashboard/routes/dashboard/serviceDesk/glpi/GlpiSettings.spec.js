import { beforeEach, describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskGlpi';
import Settings from './GlpiSettings.vue';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';
import serviceMessages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
const holder = vi.hoisted(() => ({ session: null }));
vi.mock('../composables/useServiceDesk', () => ({
  useServiceDesk: () => holder.session,
}));
vi.mock('dashboard/api/serviceDeskGlpi', () => {
  const api = { get: vi.fn(), save: vi.fn() };
  return { default: api, createServiceDeskGlpiClient: () => api };
});
const configuration = () => ({
  data: {
    contract_version: 1,
    source: 'glpi',
    account_id: '1',
    user_id: '7',
    units: [],
    members: [],
    connection: {
      base_url: 'https://glpi.example.test/apirest.php',
      timezone: 'America/Sao_Paulo',
      enabled: false,
      primary_source: 'glpi',
      user_token_configured: true,
      app_token_configured: true,
      entity_mappings: [],
      user_mappings: [],
      categories: [],
      lock_version: 0,
    },
  },
});
beforeEach(() => {
  holder.session = {
    accountId: ref('1'),
    userId: ref('7'),
    state: reactive({ status: 'ready' }),
    revalidate: vi.fn(async () => {}),
  };
  API.get.mockResolvedValue(configuration());
  API.save.mockResolvedValue(configuration());
});
describe('GLPI account source configuration', () => {
  it('preserves the backend selected GLPI source while disabled and saves it explicitly', async () => {
    const wrapper = mount(Settings, {
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en: { ...messages, ...serviceMessages } },
          }),
        ],
        stubs: {
          Button: {
            props: ['label'],
            template: '<button>{{ label }}</button>',
          },
        },
      },
    });
    await flushPromises();
    expect(
      wrapper.get('[data-testid="glpi-primary-source"]').element.value
    ).toBe('glpi');
    await wrapper.findAll('form')[0].trigger('submit');
    await flushPromises();
    expect(API.save.mock.calls[0][1]).toMatchObject({
      enabled: false,
      primary_source: 'glpi',
      categories: [],
    });
    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(holder.session.revalidate).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });
});
