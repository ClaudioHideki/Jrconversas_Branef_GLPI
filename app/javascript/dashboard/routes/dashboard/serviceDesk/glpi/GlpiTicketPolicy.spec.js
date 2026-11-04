import { beforeEach, describe, expect, it, vi } from 'vitest';
import { flushPromises, mount } from '@vue/test-utils';
import { h, reactive, ref } from 'vue';
import { createI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskGlpi';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';
import serviceMessages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import { useGlpi } from './useGlpi';
import Form from './GlpiOperationForm.vue';
import RichEditor from './GlpiRichEditor.vue';

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
const creationFields = [
  'name',
  'content',
  'type',
  'urgency',
  'impact',
  'priority',
  'itilcategories_id',
  '_users_id_requester',
];
const policy = values => ({
  entity_id: 0,
  type: 1,
  category_id: null,
  template_id: 7,
  template_source: 'entity',
  version: 'a'.repeat(64),
  fields: creationFields,
  required: ['name', 'content'],
  hidden: ['priority'],
  predefined: {
    name: 'Source title',
    content: 'Describe the issue',
    type: 1,
    urgency: 3,
    impact: 3,
    priority: 4,
  },
  predefined_html: {},
  supported: true,
  unsupported_required: [],
  ...values,
});
const render = (source = 'glpi', operation = 'ticket.create') => {
  holder.session.state.context.data_source = source;
  const wrapper = mount(
    {
      setup() {
        const glpi = useGlpi();
        glpi.state.context = {
          entities: [
            { id: 0, name: 'Root' },
            { id: 2, name: 'Branch' },
          ],
        };
        return () =>
          h(Form, {
            glpi,
            operations: [
              {
                operation,
                itemtype: 'Ticket',
                verb: operation === 'ticket.create' ? 'post' : 'patch',
                fields: creationFields,
                required: ['name', 'content', 'type', 'urgency', 'impact'],
                supported: true,
                permitted: true,
                source_allowed: true,
                parent: null,
              },
            ],
            ...(operation === 'ticket.update'
              ? { record: { id: 31, entities_id: 0, name: 'Existing' } }
              : {}),
          });
      },
    },
    {
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
            props: ['label', 'disabled', 'type'],
            template:
              '<button :type="type" :disabled="disabled">{{ label }}</button>',
          },
        },
      },
    }
  );
  return wrapper;
};
const entity = wrapper => wrapper.findAll('select')[1];
const control = (wrapper, name) => {
  const field = wrapper.get(`[data-field="${name}"]`);
  return field.find('select').exists()
    ? field.get('select')
    : field.get('input, textarea');
};
const submit = wrapper => wrapper.get('button[type="submit"]');
beforeEach(() => {
  holder.session = {
    accountId: ref('1'),
    userId: ref('7'),
    state: reactive({ status: 'ready', context: { data_source: 'glpi' } }),
  };
  API.get.mockImplementation(async (_account, path, params) =>
    path === 'ticket_form'
      ? envelope({
          form: policy({
            entity_id: Number(params.entity_id),
            type: Number(params.type),
            category_id: params.category_id || null,
          }),
        })
      : envelope({
          items: [
            { id: 5, name: 'Category' },
            { id: 7, name: 'Explicit template' },
            { id: 9, name: 'Requester' },
          ],
          meta: { page: 1, per_page: 25, total: 3 },
          coverage: { complete: true, errors: [] },
        })
  );
  API.execute.mockResolvedValue(
    envelope({
      command: { id: '81', state: 'indeterminate', technical_user_id: 9 },
    })
  );
});

describe('primary-source ticket creation policy', () => {
  it('requires the source form, preserves its rich placeholder and dynamic required controls, and omits hidden values', async () => {
    API.get.mockImplementation(async (_account, path, params) =>
      path === 'ticket_form'
        ? envelope({
            form: policy({
              category_id: params.category_id || null,
              required: [
                'name',
                'content',
                '_users_id_requester',
                'itilcategories_id',
              ],
              predefined: {
                name: 'Source title',
                content: 'Describe the issue Location',
                type: 1,
                urgency: 3,
                impact: 3,
                priority: 4,
              },
              predefined_html: {
                content:
                  '<table><tbody><tr><td>Describe the issue</td><td>Location</td></tr></tbody></table>',
              },
            }),
          })
        : envelope({
            items: [
              { id: 5, name: 'Category' },
              { id: 9, name: 'Requester' },
            ],
          })
    );
    const wrapper = render();
    expect(submit(wrapper).attributes('disabled')).toBeDefined();
    expect(API.get).not.toHaveBeenCalled();
    await entity(wrapper).setValue('0');
    await flushPromises();
    expect(
      API.get.mock.calls.some(
        call => call[1] === 'ticket_form' && call[2].type === 1
      )
    ).toBe(true);
    expect(
      wrapper.get('[data-testid="glpi-rich-editor"] table').text()
    ).toContain('Describe the issue');
    expect(
      control(wrapper, '_users_id_requester').attributes('required')
    ).toBeDefined();
    expect(
      control(wrapper, 'itilcategories_id').attributes('required')
    ).toBeDefined();
    expect(wrapper.find('[data-field="priority"]').exists()).toBe(false);
    await control(wrapper, '_users_id_requester').setValue('9');
    await control(wrapper, 'itilcategories_id').setValue('5');
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    expect(API.execute).not.toHaveBeenCalled();
    wrapper
      .getComponent(RichEditor)
      .vm.$emit(
        'update:modelValue',
        '<table><tbody><tr><td>Operator details</td></tr></tbody></table>'
      );
    await flushPromises();
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(API.execute.mock.calls[0][1]).toMatchObject({
      operation: 'ticket.create',
      entity_id: 0,
      template_version: 'a'.repeat(64),
      attributes: {
        name: 'Source title',
        content_format: 'rich',
        _users_id_requester: 9,
        itilcategories_id: 5,
      },
    });
    expect(API.execute.mock.calls[0][1].attributes).not.toHaveProperty(
      'priority'
    );
    expect(API.execute.mock.calls[0][1].attributes).not.toHaveProperty(
      'template_id'
    );
    expect(API.execute.mock.calls[0][1].attributes).not.toHaveProperty(
      '_tickettemplate'
    );
    wrapper.unmount();
  });
  it('preserves operator edits across explicit template changes while replacing untouched defaults', async () => {
    API.get.mockImplementation(async (_account, path, params) =>
      path === 'ticket_form'
        ? envelope({
            form: policy({
              template_source: params.template_id ? 'explicit' : 'entity',
              predefined: {
                name: params.template_id ? 'Other title' : 'Source title',
                content: 'Placeholder',
                type: 1,
                urgency: params.template_id ? 4 : 3,
                impact: 3,
              },
              version: (params.template_id ? 'b' : 'a').repeat(64),
            }),
          })
        : envelope({ items: [{ id: 7, name: 'Explicit template' }] })
    );
    const wrapper = render();
    await entity(wrapper).setValue('0');
    await flushPromises();
    await control(wrapper, 'name').setValue('Operator title');
    await control(wrapper, 'content').setValue('Operator details');
    await wrapper
      .get('[data-testid="glpi-template-selector"] select')
      .setValue('7');
    await flushPromises();
    expect(control(wrapper, 'name').element.value).toBe('Operator title');
    expect(control(wrapper, 'content').element.value).toBe('Operator details');
    expect(control(wrapper, 'urgency').element.value).toBe('4');
    expect(
      API.get.mock.calls.some(
        call => call[1] === 'resources/templates' && call[2].entity_id === 0
      )
    ).toBe(true);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(API.execute.mock.calls[0][1]).toMatchObject({
      template_version: 'b'.repeat(64),
      attributes: { template_id: 7, name: 'Operator title', urgency: 4 },
    });
    wrapper.unmount();
  });
  it('discards late form responses after an entity change and clears scoped selections', async () => {
    let finishOld;
    API.get.mockImplementation(async (_account, path, params) => {
      if (path !== 'ticket_form')
        return envelope({ items: [{ id: 7, name: 'Explicit template' }] });
      if (Number(params.entity_id) === 0)
        return new Promise(resolve => {
          finishOld = resolve;
        });
      return envelope({
        form: policy({
          entity_id: 2,
          version: 'b'.repeat(64),
          predefined: {
            name: 'Current entity title',
            content: 'New placeholder',
            type: 1,
            urgency: 3,
            impact: 3,
          },
        }),
      });
    });
    const wrapper = render();
    await entity(wrapper).setValue('0');
    await flushPromises();
    expect(submit(wrapper).attributes('disabled')).toBeDefined();
    await entity(wrapper).setValue('2');
    await flushPromises();
    finishOld(
      envelope({ form: policy({ predefined: { name: 'Stale title' } }) })
    );
    await flushPromises();
    expect(control(wrapper, 'name').element.value).toBe('Current entity title');
    expect(
      wrapper.get('[data-testid="glpi-template-selector"] select').element.value
    ).toBe('');
    expect(control(wrapper, '_users_id_requester').element.value).toBe('');
    expect(control(wrapper, 'itilcategories_id').element.value).toBe('');
    await control(wrapper, 'content').setValue('Current entity details');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(API.execute.mock.calls[0][1]).toMatchObject({
      entity_id: 2,
      template_version: 'b'.repeat(64),
    });
    wrapper.unmount();
  });
  it.each(['denied', 'unsupported', 'missing'])(
    'blocks %s source policy without a static-form fallback',
    async kind => {
      API.get.mockImplementation(async (_account, path) => {
        if (path !== 'ticket_form') return envelope({ items: [] });
        if (kind === 'denied')
          throw Object.assign(new Error('Denied'), {
            response: {
              status: 403,
              data: { source_code: 'ERROR_RIGHT_MISSING' },
            },
          });
        return kind === 'missing'
          ? envelope({})
          : envelope({
              form: policy({ supported: false, unsupported_required: ['42'] }),
            });
      });
      const wrapper = render();
      await entity(wrapper).setValue('0');
      await flushPromises();
      expect(submit(wrapper).attributes('disabled')).toBeDefined();
      const expectedMessage = {
        denied: 'ERROR_RIGHT_MISSING',
        unsupported: '42',
        missing: messages.JRC_GLPI.ticket_form.unavailable,
      }[kind];
      expect(
        wrapper
          .findAll('[role="alert"]')
          .some(alert => alert.text().includes(expectedMessage))
      ).toBe(true);
      await wrapper.get('form').trigger('submit');
      expect(API.execute).not.toHaveBeenCalled();
      wrapper.unmount();
    }
  );
  it.each([
    ['native', 'ticket.create'],
    ['glpi', 'ticket.update'],
  ])('does not load a ticket policy for %s %s', async (source, operation) => {
    const wrapper = render(source, operation);
    await flushPromises();
    expect(API.get.mock.calls.some(call => call[1] === 'ticket_form')).toBe(
      false
    );
    wrapper.unmount();
  });
  it('shows source-derived creation status without an editable status or a status override', async () => {
    API.get.mockImplementation(async (_account, path) =>
      path === 'ticket_form'
        ? envelope({
            form: policy({
              fields: [...creationFields, 'status'],
              predefined: {
                name: 'Title',
                content: 'Placeholder',
                type: 1,
                urgency: 3,
                impact: 3,
                status: 4,
              },
            }),
          })
        : envelope({ items: [] })
    );
    const wrapper = render();
    await entity(wrapper).setValue('0');
    await flushPromises();
    const status = wrapper.get('[data-field="status"]');
    expect(status.find('select, input').exists()).toBe(false);
    expect(status.text()).toContain(messages.JRC_GLPI.statuses['4']);
    await control(wrapper, 'content').setValue('Operator details');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(API.execute.mock.calls[0][1].attributes).not.toHaveProperty(
      'status'
    );
    wrapper.unmount();
  });
  it('keeps context selectors usable after automatic policy denial and recovers through an authorized explicit template', async () => {
    API.get.mockImplementation(async (_account, path, params) => {
      if (path !== 'ticket_form')
        return envelope({
          items: [
            { id: 7, name: 'Explicit template' },
            { id: 5, name: 'Category' },
          ],
        });
      if (!params.template_id)
        throw Object.assign(new Error('Denied default metadata'), {
          response: {
            status: 403,
            data: { source_code: 'ERROR_RIGHT_MISSING' },
          },
        });
      return envelope({ form: policy({ template_source: 'explicit' }) });
    });
    const wrapper = render();
    await entity(wrapper).setValue('0');
    await flushPromises();
    expect(
      control(wrapper, 'itilcategories_id').attributes('disabled')
    ).toBeUndefined();
    expect(control(wrapper, 'type').attributes('disabled')).toBeUndefined();
    const template = wrapper.get(
      '[data-testid="glpi-template-selector"] select'
    );
    expect(template.attributes('disabled')).toBeUndefined();
    await template.setValue('7');
    await flushPromises();
    expect(wrapper.text()).not.toContain('ERROR_RIGHT_MISSING');
    await control(wrapper, 'content').setValue('Recovered operator details');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(API.execute.mock.calls[0][1]).toMatchObject({
      template_version: 'a'.repeat(64),
      attributes: { template_id: 7 },
    });
    wrapper.unmount();
  });
  it('drops a prior operator value when the next policy hides that field', async () => {
    API.get.mockImplementation(async (_account, path, params) =>
      path === 'ticket_form'
        ? envelope({
            form: policy({
              hidden: params.template_id ? ['name'] : [],
              predefined: {
                name: params.template_id
                  ? 'Forced hidden title'
                  : 'Source title',
                content: 'Placeholder',
                type: 1,
                urgency: 3,
                impact: 3,
              },
            }),
          })
        : envelope({ items: [{ id: 7, name: 'Explicit template' }] })
    );
    const wrapper = render();
    await entity(wrapper).setValue('0');
    await flushPromises();
    await control(wrapper, 'name').setValue('Prior operator title');
    await wrapper
      .get('[data-testid="glpi-template-selector"] select')
      .setValue('7');
    await flushPromises();
    expect(wrapper.find('[data-field="name"]').exists()).toBe(false);
    await control(wrapper, 'content').setValue('Operator details');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(API.execute.mock.calls[0][1].attributes).not.toHaveProperty('name');
    wrapper.unmount();
  });
  it('clears a prepared form and scoped choices when the authenticated user changes', async () => {
    const wrapper = render();
    await entity(wrapper).setValue('0');
    await flushPromises();
    await control(wrapper, 'name').setValue('Old user draft');
    await control(wrapper, 'content').setValue('Old user details');
    const requests = API.get.mock.calls.filter(
      call => call[1] === 'ticket_form'
    ).length;
    holder.session.userId.value = '8';
    await flushPromises();
    expect(entity(wrapper).element.value).toBe('');
    expect(submit(wrapper).attributes('disabled')).toBeDefined();
    expect(wrapper.text()).not.toContain('Old user draft');
    expect(
      API.get.mock.calls.filter(call => call[1] === 'ticket_form')
    ).toHaveLength(requests);
    await wrapper.get('form').trigger('submit');
    expect(API.execute).not.toHaveBeenCalled();
    wrapper.unmount();
  });
  it('does not reload a scoped template lookup when only draft text changes', async () => {
    const wrapper = render();
    await entity(wrapper).setValue('0');
    await flushPromises();
    const lookups = API.get.mock.calls.filter(
      call => call[1] === 'resources/templates'
    ).length;
    await control(wrapper, 'name').setValue('Edited title');
    await flushPromises();
    expect(
      API.get.mock.calls.filter(call => call[1] === 'resources/templates')
    ).toHaveLength(lookups);
    wrapper.unmount();
  });
  it('shows a source-predefined requester even when it is outside the current lookup page', async () => {
    API.get.mockImplementation(async (_account, path) =>
      path === 'ticket_form'
        ? envelope({
            form: policy({
              required: ['name', 'content', '_users_id_requester'],
              predefined: {
                name: 'Title',
                content: 'Placeholder',
                type: 1,
                urgency: 3,
                impact: 3,
                _users_id_requester: 999,
              },
            }),
          })
        : envelope({ items: [{ id: 9, name: 'Other requester' }] })
    );
    const wrapper = render();
    await entity(wrapper).setValue('0');
    await flushPromises();
    expect(control(wrapper, '_users_id_requester').element.value).toBe('999');
    expect(
      control(wrapper, '_users_id_requester').get('option:checked').text()
    ).toContain('999');
    await control(wrapper, 'content').setValue('Operator details');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(API.execute.mock.calls[0][1].attributes).toMatchObject({
      _users_id_requester: 999,
    });
    wrapper.unmount();
  });
  it('re-evaluates type/category changes without replacing operator text and permits a confirmed policy without an effective model', async () => {
    API.get.mockImplementation(async (_account, path, params) =>
      path === 'ticket_form'
        ? envelope({
            form: policy({
              type: Number(params.type),
              category_id: params.category_id || null,
              template_id: null,
              template_source: 'none',
              version: (params.type === 2 ? 'b' : 'a').repeat(64),
              predefined: {
                name: 'Source title',
                content:
                  params.type === 2
                    ? 'Request placeholder'
                    : 'Incident placeholder',
                type: Number(params.type),
                urgency: 3,
                impact: 3,
              },
            }),
          })
        : envelope({ items: [{ id: 5, name: 'Category' }] })
    );
    const wrapper = render();
    await entity(wrapper).setValue('0');
    await flushPromises();
    await control(wrapper, 'name').setValue('Operator title');
    await control(wrapper, 'type').setValue('2');
    await flushPromises();
    expect(control(wrapper, 'name').element.value).toBe('Operator title');
    expect(control(wrapper, 'content').element.value).toBe(
      'Request placeholder'
    );
    await control(wrapper, 'itilcategories_id').setValue('5');
    await flushPromises();
    expect(
      API.get.mock.calls.some(
        call =>
          call[1] === 'ticket_form' &&
          call[2].type === 2 &&
          call[2].category_id === 5
      )
    ).toBe(true);
    await wrapper.get('form').trigger('submit');
    expect(API.execute).not.toHaveBeenCalled();
    await control(wrapper, 'content').setValue('Operator request details');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(API.execute.mock.calls[0][1]).toMatchObject({
      template_version: 'b'.repeat(64),
      attributes: { type: 2, itilcategories_id: 5 },
    });
    expect(API.execute.mock.calls[0][1].attributes).not.toHaveProperty(
      'template_id'
    );
    wrapper.unmount();
  });
});
