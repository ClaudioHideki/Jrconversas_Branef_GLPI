import { describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import Component from './GlpiTicketAnalysis.vue';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';

const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
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
    wrapper.findComponent({ name: 'GlpiFilters' }).vm.$emit('apply', {
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

describe('selected ticket actions', () => {
  const setup = (canAnalyzeBatch = false) => {
    const state = reactive({
      context: { entities: [], can_analyze_batch: canAnalyzeBatch },
      data: {
        analysisTickets: {
          items: [
            { id: 22, title: 'Two' },
            { id: 11, title: 'One' },
          ],
          meta: { total: canAnalyzeBatch ? 120 : 2 },
          coverage: { state: 'complete' },
        },
      },
      loading: {},
      errors: {},
    });
    const glpi = {
      state,
      session: { accountId: { value: '3' } },
      read: vi.fn(),
      discard: vi.fn(),
      API: {
        get: vi.fn(async () => ({ batch: null })),
        startSentimentBatch: vi.fn(async () => ({
          batch: {
            id: '44',
            state: 'queued',
            counts: { queued: 120 },
            total: 120,
            processed: 0,
            filters: { from: '2026-10-01', to: '2026-12-01' },
          },
        })),
        analyzeSentiment: vi.fn(async (_account, id) => ({
          analysis: { ticket_id: Number(id), status: 'no_public_text' },
        })),
      },
      run: vi.fn(async (_key, action) =>
        action('3', new AbortController().signal)
      ),
    };
    const wrapper = mount(Component, {
      props: {
        glpi,
        initialFilters: canAnalyzeBatch
          ? { from: '2026-10-01', to: '2026-11-30' }
          : {},
      },
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
          GlpiBadge: true,
          Button: {
            props: ['label', 'disabled'],
            template: '<button :disabled="disabled">{{label}}</button>',
          },
        },
      },
    });
    return { wrapper, glpi, state };
  };
  it('starts a server batch for the whole filter without sending visible page IDs', async () => {
    const { wrapper, glpi } = setup(true);
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Analisar todos do filtro (120)')
      .trigger('click');
    await flushPromises();
    expect(glpi.API.startSentimentBatch).toHaveBeenCalledWith(
      '3',
      { from: '2026-10-01', to: '2026-12-01' },
      expect.any(AbortSignal)
    );
    expect(glpi.API.analyzeSentiment).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('opens the real JRC ticket and analyzes selected IDs sequentially without asking for dates', async () => {
    const { wrapper, glpi } = setup();
    push.mockClear();
    await wrapper
      .findAll('button')
      .find(b => b.text() === 'Abrir chamado')
      .trigger('click');
    expect(push).toHaveBeenCalledWith(
      expect.objectContaining({ params: { accountId: '3', ticketId: 22 } })
    );
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper
      .findAll('button')
      .find(b => b.text() === 'Analisar selecionados (2)')
      .trigger('click');
    await flushPromises();
    expect(
      glpi.API.analyzeSentiment.mock.calls.map(c => c.slice(0, 3))
    ).toEqual([
      ['3', '22', { scope: 'ticket' }],
      ['3', '11', { scope: 'ticket' }],
    ]);
    const report = wrapper.get('[data-testid="analysis-report-list"]').text();
    expect(report.indexOf('#11')).toBeLessThan(report.indexOf('#22'));
    wrapper.unmount();
  });
  it('discards late batch results when the authorized context changes', async () => {
    const { wrapper, glpi, state } = setup();
    let finish;
    glpi.run.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper
      .findAll('button')
      .find(b => b.text() === 'Analisar selecionados (2)')
      .trigger('click');
    state.context = { entities: [] };
    await flushPromises();
    finish({ analysis: { ticket_id: 22, status: 'no_public_text' } });
    await flushPromises();
    expect(wrapper.find('[data-testid="analysis-report-list"]').exists()).toBe(
      false
    );
    expect(glpi.run).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });
});
