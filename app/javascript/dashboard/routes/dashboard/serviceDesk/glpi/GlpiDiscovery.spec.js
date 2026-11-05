import { describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';
import serviceMessages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import Form from './GlpiOperationForm.vue';
import Board from './GlpiResourceBoard.vue';
import Workspace from './GlpiTicketWorkspace.vue';

const holder = vi.hoisted(() => ({ glpi: null }));
vi.mock('./useGlpi', () => ({ useGlpi: () => holder.glpi }));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
const global = () => ({
  plugins: [
    createI18n({
      legacy: false,
      locale: 'en',
      messages: { en: { ...messages, ...serviceMessages } },
    }),
  ],
  stubs: {
    Button: {
      props: ['label', 'disabled', 'type'],
      template:
        '<button :type="type" :disabled="disabled">{{ label }}</button>',
    },
    Pagination: true,
    GlpiFilters: true,
  },
});
const glpi = (admin = true) => {
  const state = reactive({
    context: { entities: [{ id: 0, name: 'Root' }], can_manage_trash: admin },
    data: {},
    errors: {},
    loading: {},
  });
  const execute = vi.fn(async () => ({
    data: { command: { state: 'succeeded', remote_id: 201 } },
  }));
  holder.glpi = {
    state,
    session: {
      accountId: ref('1'),
      userId: ref('7'),
      state: { status: 'ready', context: { data_source: 'glpi' } },
    },
    API: { execute },
    discard: vi.fn(key => delete state.data[key]),
    read: vi.fn(async (key, path) => {
      let result = { items: [], meta: { total: 0 } };
      if (path.includes('asset_candidates/')) {
        result = {
          item: {
            id: 201,
            name: 'Synthetic laptop',
            itemtype: 'Computer',
            serial: 'LAB123',
            entities_id: 0,
          },
        };
      } else if (path.includes('asset_candidates')) {
        result = {
          items: [
            {
              id: 201,
              name: 'Synthetic laptop',
              itemtype: 'Computer',
              entities_id: 0,
            },
          ],
          meta: { total: 1 },
        };
      } else if (path === 'trash') {
        result = {
          items: [{ id: 101, title: 'Deleted synthetic', is_deleted: true }],
          meta: { page: 1, per_page: 25, total: 1 },
        };
      } else if (path === 'trash/101') {
        result = {
          ticket: {
            id: 101,
            title: 'Deleted synthetic',
            entities_id: 0,
            is_deleted: 1,
          },
          source_version: 'revision',
        };
      }
      state.data[key] = result;
      return result;
    }),
    run: async (_key, action) => (await action('1')).data,
  };
  return holder.glpi;
};

describe('service scoped discovery', () => {
  it('selects a discovered typed asset and uses the existing association command', async () => {
    const client = glpi();
    const wrapper = mount(Form, {
      props: {
        glpi: client,
        parentId: 101,
        authorizedEntityId: 0,
        parentVersion: 'revision',
        operations: [
          {
            operation: 'asset.create',
            verb: 'post',
            parent: 'Ticket',
            fields: ['itemtype', 'items_id'],
            required: ['itemtype', 'items_id'],
            supported: true,
            permitted: true,
            source_allowed: true,
          },
        ],
      },
      global: global(),
    });
    await wrapper.get('[data-field="itemtype"] select').setValue('Computer');
    await flushPromises();
    expect(client.read).toHaveBeenCalledWith(
      'lookup',
      'resources/asset_candidates',
      expect.objectContaining({ ticket_id: 101, asset_type: 'Computer' })
    );
    await wrapper.get('[data-field="items_id"] select').setValue(201);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(client.API.execute.mock.calls[0][1]).toMatchObject({
      operation: 'asset.create',
      target_id: null,
      entity_id: 0,
      attributes: { parent_id: 101, itemtype: 'Computer', items_id: 201 },
      expected_version: 'revision',
    });
    wrapper.unmount();
  });
  it('consults a linked asset target separately from its association id', async () => {
    const client = glpi();
    client.state.data.capabilities = {
      operations: [
        {
          operation: 'asset.delete',
          verb: 'delete',
          parent: 'Ticket',
          fields: [],
          required: [],
          supported: true,
          permitted: true,
          source_allowed: true,
        },
      ],
    };
    client.state.data['resource:tickets:101:assets'] = {
      items: [{ id: 99, tickets_id: 101, itemtype: 'Computer', items_id: 201 }],
      meta: {},
    };
    client.read.mockImplementation(async (key, path) => {
      if (path === 'resources/asset_candidates/201')
        return {
          item: { id: 201, name: 'Synthetic laptop', serial: 'LAB123' },
        };
      return client.state.data[key];
    });
    const wrapper = mount(Board, {
      props: {
        glpi: client,
        resource: 'assets',
        parentId: 101,
        parentEntityId: 0,
      },
      global: global(),
    });
    await wrapper.find('button[aria-pressed]').trigger('click');
    await flushPromises();
    expect(client.read).toHaveBeenCalledWith(
      expect.any(String),
      'resources/asset_candidates/201',
      { ticket_id: 101, asset_type: 'Computer' }
    );
    expect(wrapper.text()).toContain('Synthetic laptop');
    expect(wrapper.text()).toContain('LAB123');
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('form input[maxlength="1000"]').setValue('Synthetic unlink');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(client.API.execute.mock.calls[0][1]).toMatchObject({
      operation: 'asset.delete',
      target_id: 99,
      attributes: { parent_id: 101 },
    });
    wrapper.unmount();
  });
  it('discovers deleted tickets only through the separate admin trash path and shows confirmed restore', async () => {
    const client = glpi();
    client.state.data.capabilities = {
      operations: [
        {
          operation: 'ticket.restore',
          verb: 'patch',
          fields: [],
          required: [],
          supported: true,
          permitted: true,
          source_allowed: true,
          confirmation: true,
        },
        {
          operation: 'ticket.update',
          verb: 'patch',
          fields: ['name'],
          required: [],
          supported: true,
          permitted: true,
        },
      ],
    };
    const wrapper = mount(Workspace, {
      props: { glpi: client },
      global: global(),
    });
    await wrapper.get('[data-testid="glpi-trash-toggle"]').trigger('click');
    await flushPromises();
    expect(client.read).toHaveBeenCalledWith(
      'tickets',
      'trash',
      expect.any(Object)
    );
    await wrapper
      .findAll('button')
      .find(button => button.text() === 'Deleted synthetic')
      .trigger('click');
    await flushPromises();
    expect(client.read).toHaveBeenCalledWith('detail', 'trash/101');
    expect(
      wrapper.get('[data-testid="glpi-deleted-state"]').text()
    ).toBeTruthy();
    expect(
      wrapper.findAll('option').map(option => option.element.value)
    ).toContain('ticket.restore');
    expect(
      wrapper.findAll('option').map(option => option.element.value)
    ).not.toContain('ticket.update');
    expect(wrapper.find('input[type="checkbox"]').exists()).toBe(true);
    await wrapper.get('form').trigger('submit');
    expect(client.API.execute).not.toHaveBeenCalled();
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(client.API.execute.mock.calls[0][1]).toMatchObject({
      operation: 'ticket.restore',
      target_id: 101,
      entity_id: 0,
      expected_version: 'revision',
    });
    wrapper.unmount();
  });
  it('does not offer trash discovery to agents', () => {
    const wrapper = mount(Workspace, {
      props: { glpi: glpi(false) },
      global: global(),
    });
    expect(wrapper.find('[data-testid="glpi-trash-toggle"]').exists()).toBe(
      false
    );
    wrapper.unmount();
  });
});
