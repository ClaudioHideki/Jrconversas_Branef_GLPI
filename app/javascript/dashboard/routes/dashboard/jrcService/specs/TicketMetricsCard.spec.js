import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import TicketMetricsCard from '../TicketMetricsCard.vue';
import messages from 'dashboard/i18n/locale/en/jrcCockpit.json';

const render = metrics =>
  mount(TicketMetricsCard, {
    props: { metrics },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
    },
  });

describe('authorized ticket indicator', () => {
  it('keeps unavailable distinct from a valid empty collection', () => {
    const unavailable = render({
      source: 'GLPI',
      state: 'unavailable',
      total: null,
      filters: {},
    });
    expect(unavailable.find('[data-testid="ticket-total"]').text()).toBe('—');
    const empty = render({
      source: 'GLPI',
      state: 'complete',
      total: 0,
      filters: {},
    });
    expect(empty.find('[data-testid="ticket-total"]').text()).toBe('0');
  });
  it('exposes the exact server filters with its navigation event', async () => {
    const wrapper = render({
      source: 'GLPI',
      state: 'partial',
      total: 2,
      route_name: 'tickets',
      filters: { from: '2026-11-01', to: '2026-11-13' },
    });
    await wrapper.find('button').trigger('click');
    expect(wrapper.emitted('navigate')[0][0]).toEqual({
      name: 'tickets',
      query: { from: '2026-11-01', to: '2026-11-13' },
    });
    expect(wrapper.text()).toContain('parcial');
  });
});
