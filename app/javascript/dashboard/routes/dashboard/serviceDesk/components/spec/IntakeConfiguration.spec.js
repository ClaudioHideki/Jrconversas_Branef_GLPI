import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import IntakeConfiguration from '../IntakeConfiguration.vue';
import API from 'dashboard/api/serviceDeskIntake';
import messages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';

vi.mock('dashboard/api/serviceDeskIntake', () => ({
  default: {
    inboxes: vi.fn(),
    get: vi.fn(),
    preview: vi.fn(),
    publish: vi.fn(),
  },
}));
const record = {
  id: '4',
  revision: 1,
  inbox_id: '2',
  mode: 'on_handoff',
  enabled: true,
  catalogue: { schema: 'jrc-service-desk-intake/1', revision: 1, systems: [] },
  responses: [],
  mappings: {},
  remote_writes_enabled: false,
};
const scoped = values => ({
  data: { account_id: '1', user_id: '7', ...values },
});
const build = () =>
  mount(IntakeConfiguration, {
    props: { accountId: '1', userId: '7' },
    global: {
      plugins: [
        createI18n({ legacy: false, locale: 'en', messages: { en: messages } }),
      ],
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  API.inboxes.mockResolvedValue(
    scoped({ inboxes: [{ id: '2', name: 'Synthetic test inbox' }] })
  );
  API.get.mockResolvedValue(scoped({ record }));
  API.preview.mockResolvedValue(
    scoped({
      ready: false,
      blockers: ['intake_sla_unmapped', 'intake_requester_unmapped'],
    })
  );
});
describe('Intake configuration readiness', () => {
  it('clears the busy state when leaving an account during a readiness request', async () => {
    let finish;
    API.preview.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = build();
    await flushPromises();
    await wrapper.get('[data-testid="intake-preview"]').trigger('click');
    API.inboxes.mockResolvedValue({
      data: {
        account_id: '2',
        user_id: '7',
        inboxes: [{ id: '5', name: 'Other synthetic inbox' }],
      },
    });
    API.get.mockResolvedValue({
      data: {
        account_id: '2',
        user_id: '7',
        record: { ...record, inbox_id: '5' },
      },
    });
    await wrapper.setProps({ accountId: '2' });
    await flushPromises();
    expect(wrapper.get('[data-testid="intake-publish"]').element.disabled).toBe(
      false
    );
    finish(scoped({ ready: true, blockers: [] }));
    await flushPromises();
    expect(wrapper.find('[data-testid="intake-readiness"]').exists()).toBe(
      false
    );
  });
  it('keeps real writes disabled when source mappings or calendar are missing', async () => {
    const wrapper = build();
    await flushPromises();
    await wrapper.get('[data-testid="intake-preview"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-testid="intake-readiness"]').text()).toContain(
      'intake_sla_unmapped'
    );
    expect(
      wrapper.get('[data-testid="intake-real-writes"]').attributes('disabled')
    ).toBeDefined();
    expect(API.publish).not.toHaveBeenCalled();
  });
  it('publishes a new test revision without granting roster permissions', async () => {
    API.publish.mockResolvedValue(
      scoped({ record: { ...record, revision: 2 } })
    );
    const wrapper = build();
    await flushPromises();
    await wrapper.get('[data-testid="intake-publish"]').trigger('click');
    await flushPromises();
    expect(API.publish).toHaveBeenCalledTimes(1);
    expect(API.publish.mock.calls[0][1]).toMatchObject({
      inbox_id: '2',
      expected_revision: 1,
      remote_writes_enabled: false,
    });
    expect(wrapper.find('[data-testid="intake-invite"]').exists()).toBe(false);
  });
  it('rejects a stale cross-account response rather than showing its catalogue', async () => {
    API.get.mockResolvedValue({
      data: { account_id: '99', user_id: '7', record },
    });
    const wrapper = build();
    await flushPromises();
    expect(wrapper.get('[role="alert"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="intake-publish"]').exists()).toBe(false);
  });
});
