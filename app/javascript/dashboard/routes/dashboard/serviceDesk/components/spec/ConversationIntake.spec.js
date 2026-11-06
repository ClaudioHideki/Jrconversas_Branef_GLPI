import { beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskIntake';
import messages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import ConversationIntake from '../ConversationIntake.vue';
vi.mock('dashboard/api/serviceDeskIntake', () => ({
  default: { demands: vi.fn(), notice: vi.fn(), complete: vi.fn() },
}));
const row = {
  id: '9',
  state: 'test_only',
  remote_id: null,
  lifecycle_state: 'active',
  selection: { system: 'example', subject_label: 'Synthetic access' },
  notifications: [],
  permissions: { notify: true, complete: true },
};
const build = () =>
  mount(ConversationIntake, {
    props: { accountId: '1', userId: '7', conversationId: '12' },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  API.demands.mockResolvedValue({
    data: { account_id: '1', user_id: '7', demands: [structuredClone(row)] },
  });
});
describe('Conversation intake observation', () => {
  it('reads metadata only on expansion and never takes over the bot or fabricates a protocol', async () => {
    const wrapper = build();
    expect(API.demands).not.toHaveBeenCalled();
    await wrapper.get('summary').trigger('click');
    await flushPromises();
    expect(API.demands).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).toContain('No confirmed GLPI number');
    expect(wrapper.text()).toContain('Synthetic access');
    expect(API.notice).not.toHaveBeenCalled();
    expect(API.complete).not.toHaveBeenCalled();
  });
  it('shows the confirmed remote reference separately from lifecycle state', async () => {
    API.demands.mockResolvedValue({
      data: {
        account_id: '1',
        user_id: '7',
        demands: [
          {
            ...row,
            state: 'confirmed',
            remote_id: '501',
            lifecycle_state: 'awaiting_information',
          },
        ],
      },
    });
    const wrapper = build();
    await wrapper.get('summary').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('GLPI ticket #501');
    expect(wrapper.text()).toContain('awaiting_information');
    expect(
      wrapper.find('[data-testid="intake-send-notice"]').element.disabled
    ).toBe(true);
  });
  it('clears the previous conversation metadata on account navigation', async () => {
    const wrapper = build();
    await wrapper.get('summary').trigger('click');
    await flushPromises();
    await wrapper.setProps({ accountId: '2', conversationId: '1' });
    await flushPromises();
    expect(wrapper.text()).not.toContain('Synthetic access');
  });
});
