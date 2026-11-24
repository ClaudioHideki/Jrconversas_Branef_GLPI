import { describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import Component from './GlpiTicketSentiment.vue';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';

const setup = (allowed = true, wholeTicket = false) => {
  const state = reactive({ loading: {}, errors: {}, data: {} });
  const glpi = {
    state,
    session: {
      state: reactive({
        context: {
          available: true,
          capabilities: { reports: { index: allowed } },
        },
      }),
    },
    API: {
      analyzeSentiment: vi.fn(async () => ({
        analysis: { ticket_id: 101, status: 'no_public_text' },
      })),
    },
    run: vi.fn(async (key, action) => {
      state.data[key] = await action('3', new AbortController().signal);
    }),
    discard: vi.fn(key => {
      delete state.data[key];
    }),
  };
  const wrapper = mount(Component, {
    props: { glpi, ticketId: 101, wholeTicket },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
      stubs: {
        Button: {
          props: ['label', 'disabled'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
      },
    },
  });
  return { wrapper, glpi, state };
};
const chooseOctober = async wrapper => {
  const fields = wrapper.findAll('input[type="date"]');
  await fields[0].setValue('2026-10-01');
  await fields[1].setValue('2026-10-31');
};
describe('GLPI ticket text sentiment in the existing Service Desk', () => {
  it('analyzes the selected ticket without asking for dates again', async () => {
    const { wrapper, glpi } = setup(true, true);
    expect(wrapper.find('input[type="date"]').exists()).toBe(false);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(glpi.API.analyzeSentiment).toHaveBeenCalledWith(
      '3',
      '101',
      { scope: 'ticket' },
      expect.any(AbortSignal)
    );
    expect(wrapper.emitted('completed')[0][0].ticket_id).toBe(101);
    wrapper.unmount();
  });
  it('does not offer analysis without the native reporting capability', () => {
    const { wrapper, glpi } = setup(false);
    expect(wrapper.find('form').exists()).toBe(false);
    expect(glpi.run).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('submits the actual ticket and inclusive date selection once, without presenting empty text as a sentiment', async () => {
    const { wrapper, glpi } = setup();
    await chooseOctober(wrapper);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(glpi.API.analyzeSentiment).toHaveBeenCalledWith(
      '3',
      '101',
      { from: '2026-10-01', to: '2026-11-01' },
      expect.any(AbortSignal)
    );
    expect(wrapper.text()).toContain(messages.JRC_GLPI.sentiment.no_text);
    expect(wrapper.find('[data-testid="glpi-sentiment-result"]').exists()).toBe(
      false
    );
    await wrapper.get('form').trigger('submit');
    expect(glpi.API.analyzeSentiment).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });
  it('clears previous results on period or ticket changes and does not render a late response from a previous ticket', async () => {
    const { wrapper, state, glpi } = setup();
    await chooseOctober(wrapper);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    await wrapper.findAll('input')[1].setValue('2026-11-30');
    expect(wrapper.text()).not.toContain(messages.JRC_GLPI.sentiment.no_text);
    await wrapper.setProps({ ticketId: 202 });
    state.data['sentiment:101'] = {
      analysis: { ticket_id: 101, status: 'no_public_text' },
    };
    await flushPromises();
    expect(wrapper.text()).not.toContain(messages.JRC_GLPI.sentiment.no_text);
    expect(wrapper.findAll('input')[0].element.value).toBe('');
    expect(glpi.discard).toHaveBeenCalledWith('sentiment:101');
    wrapper.unmount();
  });
  it('shows unknown authorship without a score, provenance, a partial window and only the confirmed token receipt', async () => {
    const { wrapper, state, glpi } = setup();
    glpi.API.analyzeSentiment.mockResolvedValue({
      analysis: {
        ticket_id: 101,
        status: 'analyzed',
        model: 'account-model',
        period: {
          from: '2026-11-01T00:00:00-03:00',
          to_exclusive: '2026-11-23T17:00:00-03:00',
          timezone: 'America/Sao_Paulo',
          partial: true,
        },
        usage: { input_tokens: 12, output_tokens: 9, total_tokens: 21 },
        source_window: {
          analyzed_records: 2,
          omitted_records: 1,
          truncated_records: 1,
        },
        report: {
          summary: 'Amostra pública sintética',
          customer_sentiment: 'insufficient_data',
          agent_sentiment: 'insufficient_data',
          quality_score: null,
          risks: [],
          recommendations: [],
          evidence: [
            { message_id: 'ITILFollowup/22', observation: 'Texto da amostra' },
          ],
          limitations: 'Autoria não comprovada',
        },
      },
    });
    await chooseOctober(wrapper);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.text()).toContain(messages.JRC_GLPI.sentiment.partial);
    expect(wrapper.text()).toContain('ITILFollowup/22');
    expect(wrapper.text()).toContain('Entrada: 12; saída: 9; total: 21.');
    expect(wrapper.text()).toContain('Evidência insuficiente');
    expect(wrapper.text()).not.toContain('estimado');
    state.errors['sentiment:101'] = { code: 'provider_rate_limited' };
    delete state.data['sentiment:101'];
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toContain(
      'provider_rate_limited'
    );
    expect(wrapper.find('[data-testid="glpi-sentiment-result"]').exists()).toBe(
      false
    );
    wrapper.unmount();
  });
});
