import { beforeEach, describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';
import serviceMessages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import { contextPayload } from '../__tests__/fixtures';

const holder = vi.hoisted(() => ({ session: null }));
vi.mock('../composables/useServiceDesk', () => ({
  provideServiceDesk: () => holder.session,
  useServiceDesk: () => holder.session,
}));
import Layout from '../ServiceDeskLayout.vue';

beforeEach(() => {
  holder.session = {
    state: reactive({ status: 'ready', context: contextPayload() }),
    accountId: ref('1'), userId: ref('7'), enabled: ref(true),
    operations: { state: {} },
  };
});

const render = async (screen, dataSource) => {
  holder.session.state.context.data_source = dataSource;
  const router = createRouter({ history: createMemoryHistory(), routes: [{
    path: '/', component: { template: '<div>Native ticket editor</div>' },
    meta: { serviceDeskScreen: screen },
  }] });
  await router.push('/');
  const wrapper = mount(Layout, { global: {
    plugins: [router, createI18n({ legacy: false, locale: 'en', messages: { en: { ...messages, ...serviceMessages } } })],
    stubs: {
      GlpiServiceDesk: { props: ['screen'], template: '<div data-testid="glpi-source">{{ screen }}</div>' },
      Breadcrumb: true, ScreenGuidance: true, WriteFeedback: true, Icon: true,
      Button: { props: ['label'], template: '<button>{{ label }}</button>' },
    },
  } });
  await flushPromises();
  return wrapper;
};

describe('Service Desk primary source', () => {
  it.each([undefined, 'native'])('keeps native operational routes for %s', async source => {
    const wrapper = await render('tickets', source);
    expect(wrapper.text()).toContain('Native ticket editor');
    expect(wrapper.find('[data-testid="glpi-source"]').exists()).toBe(false);
    wrapper.unmount();
  });
  it.each(['overview', 'tickets', 'mine', 'sla', 'detail', 'edit'])('mounts GLPI instead of a native controller on %s', async screen => {
    const wrapper = await render(screen, 'glpi');
    expect(wrapper.find('[data-testid="glpi-source"]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain('Native ticket editor');
    wrapper.unmount();
  });
  it('keeps JRC configuration clearly identified', async () => {
    holder.session.state.context.capabilities.settings = { index: true };
    const wrapper = await render('settings', 'glpi');
    expect(wrapper.text()).toContain('Native ticket editor');
    expect(wrapper.text()).toContain('JRC');
    wrapper.unmount();
  });
});
