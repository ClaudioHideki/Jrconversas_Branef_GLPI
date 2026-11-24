import { describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import Component from './GlpiTicketAnalysis.vue';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';

describe('ticket analysis selection', () => {
  it('loads a scoped list without inference and passes the inclusive period only to the candidate query', async () => {
    const glpi = {
      state: reactive({ context: { entities: [] }, data: {}, loading: {} }),
      read: vi.fn(),
      discard: vi.fn(),
    };
    const wrapper = mount(Component, {
      props: { glpi },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en: messages },
          }),
        ],
        stubs: {
          GlpiFilters: true,
          GlpiTicketSentiment: true,
          GlpiCoverage: true,
          Pagination: true,
        },
      },
    });
    expect(glpi.read).toHaveBeenCalledWith('analysisTickets', 'tickets', {
      page: 1,
      per_page: 25,
    });
    wrapper
      .findComponent({ name: 'GlpiFilters' })
      .vm.$emit('apply', {
        from: '2026-10-01',
        to: '2026-10-31',
        search: '4152',
      });
    await flushPromises();
    expect(glpi.read).toHaveBeenLastCalledWith(
      'analysisTickets',
      'sentiment/candidates',
      {
        from: '2026-10-01',
        to: '2026-11-01',
        search: '4152',
        page: 1,
        per_page: 25,
      }
    );
    const count = glpi.read.mock.calls.length;
    wrapper
      .findComponent({ name: 'GlpiFilters' })
      .vm.$emit('apply', { from: '2026-10-01' });
    await flushPromises();
    expect(glpi.read).toHaveBeenCalledTimes(count);
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(
      wrapper.findComponent({ name: 'GlpiTicketSentiment' }).exists()
    ).toBe(false);
    wrapper.unmount();
  });
});
