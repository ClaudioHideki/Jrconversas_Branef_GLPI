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
  const api = { get: vi.fn(), execute: vi.fn() };
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
  it('reaches category operations from the remote catalogue and updates the selected source record', async () => {
    API.get.mockImplementation(async (_account, path) => {
      if (path === 'context')
        return envelope({
          available: true,
          entities: [{ id: 0, name: 'Root' }],
        });
      if (path === 'capabilities')
        return envelope({
          operations: ['create', 'update', 'delete'].map(action => ({
            operation: `category.${action}`,
            itemtype: 'ITILCategory',
            verb: { create: 'post', update: 'patch', delete: 'delete' }[action],
            supported: true,
            permitted: true,
            source_allowed: true,
            fields: action === 'delete' ? [] : ['name'],
            required: action === 'create' ? ['name'] : [],
            parent: null,
          })),
        });
      return envelope({
        items:
          path === 'resources/categories'
            ? [
                {
                  id: 31,
                  name: 'Remote category',
                  entities_id: 0,
                  date_mod: '2026-11-04 10:00:00',
                },
              ]
            : [{ id: 42, name: 'Remote template' }],
        meta: { page: 1, per_page: 25, total: 1 },
        coverage: { complete: true, errors: [] },
      });
    });
    API.execute.mockResolvedValue(
      envelope({
        command: { id: '81', state: 'indeterminate', technical_user_id: 9 },
      })
    );
    const global = globals();
    global.stubs.GlpiResourceBoard = false;
    const wrapper = mount(GlpiServiceDesk, {
      props: { screen: 'catalog' },
      global,
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Remote template');
    const categoriesButton = wrapper
      .findAll('button')
      .find(button => button.text() === 'Categorias GLPI');
    expect(
      categoriesButton,
      'remote categories must be reachable from the catalogue'
    ).toBeDefined();
    await categoriesButton.trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Remote category');
    expect(wrapper.text()).not.toContain('Remote template');
    const form = wrapper.get('[data-testid="glpi-operation-form"]');
    expect(
      form
        .findAll('select')[0]
        .findAll('option')
        .map(option => option.element.value)
    ).toEqual(['category.create', 'category.update', 'category.delete']);
    await wrapper
      .findAll('button')
      .find(button => button.text().includes('Remote category'))
      .trigger('click');
    await form.findAll('select')[0].setValue('category.update');
    await form.get('input[type="text"]').setValue('Updated remote category');
    await form.get('form').trigger('submit');
    await flushPromises();
    expect(API.execute.mock.calls[0][1]).toMatchObject({
      operation: 'category.update',
      target_id: 31,
      entity_id: 0,
      attributes: { name: 'Updated remote category' },
      expected_version: '2026-11-04 10:00:00',
    });
    expect(
      wrapper.get('[data-testid="glpi-command-receipt"]').text()
    ).toContain(messages.JRC_GLPI.receipts.indeterminate);
    wrapper.unmount();
  });
  it('shows a denied remote category collection without an empty success or template records', async () => {
    API.get.mockImplementation(async (_account, path) => {
      if (path === 'context')
        return envelope({ available: true, entities: [] });
      if (path === 'capabilities') return envelope({ operations: [] });
      if (path === 'resources/categories')
        throw Object.assign(new Error('Source denied categories'), {
          response: {
            status: 403,
            data: { source_code: 'ERROR_RIGHT_MISSING' },
          },
        });
      return envelope({
        items: [{ id: 42, name: 'Remote template' }],
        coverage: { complete: true, errors: [] },
      });
    });
    const global = globals();
    global.stubs.GlpiResourceBoard = false;
    const wrapper = mount(GlpiServiceDesk, {
      props: { screen: 'catalog' },
      global,
    });
    await flushPromises();
    const categoriesButton = wrapper
      .findAll('button')
      .find(button => button.text() === 'Categorias GLPI');
    expect(
      categoriesButton,
      'remote categories must be reachable from the catalogue'
    ).toBeDefined();
    await categoriesButton.trigger('click');
    await flushPromises();
    const categories = wrapper.get('[data-testid="glpi-resource-categories"]');
    expect(categories.get('[role="alert"]').text()).toContain(
      'ERROR_RIGHT_MISSING'
    );
    expect(categories.text()).not.toContain(messages.JRC_GLPI.empty_history);
    expect(wrapper.text()).not.toContain('Remote template');
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Modelos GLPI')
      .trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('Remote template');
    wrapper.unmount();
  });
});
