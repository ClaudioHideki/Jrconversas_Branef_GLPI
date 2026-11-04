import { describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';
import serviceMessages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import Form from './GlpiOperationForm.vue';

const render = (
  operation,
  record = null,
  parentId = null,
  authorizedEntityId = null,
  parentVersion = ''
) => {
  const execute = vi.fn(async () => ({
    data: { command: { id: '81', state: 'indeterminate' } },
  }));
  const glpi = {
    state: reactive({
      context: { entities: [{ id: 0, name: 'Root' }] },
      loading: {},
      errors: {},
      data: {},
    }),
    API: { execute },
    read: vi.fn(),
    run: async (_key, action) =>
      (await action('1', new AbortController().signal)).data,
  };
  const wrapper = mount(Form, {
    props: {
      glpi,
      operations: [operation],
      record,
      parentId,
      authorizedEntityId,
      parentVersion,
    },
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
          props: ['label', 'disabled'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
        GlpiLookup: true,
      },
    },
  });
  return { wrapper, glpi, execute };
};
const descriptor = values => ({
  operation: 'ticket.update',
  fields: ['name', 'content'],
  required: [],
  supported: true,
  permitted: true,
  source_allowed: true,
  verb: 'patch',
  parent: null,
  ...values,
});

describe('GLPI human operation forms', () => {
  it('updates only fields the operator changed and preserves existing rich content', async () => {
    const { wrapper, execute } = render(descriptor(), {
      id: 20,
      entities_id: 0,
      title: 'Old',
      description: 'Cell',
      description_html: '<table><tbody><tr><td>Cell</td></tr></tbody></table>',
      date_mod: '2026-11-04 10:00:00',
    });
    await wrapper.get('input[type="text"]').setValue('New title');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(execute.mock.calls[0][1]).toMatchObject({
      operation: 'ticket.update',
      target_id: 20,
      entity_id: 0,
      attributes: { name: 'New title' },
      expected_version: '2026-11-04 10:00:00',
    });
    expect(execute.mock.calls[0][1].attributes).not.toHaveProperty('content');
    wrapper.unmount();
  });
  it('posts a child with explicit parent_id and no child target and keeps zero values', async () => {
    const { wrapper, execute } = render(
      descriptor({
        operation: 'followup.create',
        fields: ['content', 'is_private'],
        required: ['content'],
        parent: 'Ticket',
        verb: 'post',
      }),
      null,
      20
    );
    await wrapper.findAll('select')[1].setValue(0);
    await wrapper.get('textarea').setValue('Public note');
    const privacy = wrapper.findAll('select').at(-1);
    if (privacy.element.options.length > 1) await privacy.setValue(0);
    else await wrapper.get('input[type="number"]').setValue(0);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(execute.mock.calls[0][1]).toMatchObject({
      target_id: null,
      entity_id: 0,
      attributes: { content: 'Public note', is_private: 0, parent_id: 20 },
    });
    expect(wrapper.text()).toContain(messages.JRC_GLPI.receipts.indeterminate);
    expect(wrapper.emitted('succeeded')).toBeUndefined();
    await wrapper.get('form').trigger('submit');
    expect(execute).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });
  it('edits planning dates in the source timezone and sends canonical seconds', async () => {
    const { wrapper, execute } = render(
      descriptor({
        operation: 'task.update',
        fields: ['begin'],
        parent: 'Ticket',
      }),
      {
        id: 5,
        entities_id: 0,
        tickets_id: 20,
        begin: '2026-11-04 10:00:00',
        date_mod: '2026-11-04 09:00:00',
      },
      20
    );
    expect(wrapper.get('input[type="datetime-local"]').element.value).toBe(
      '2026-11-04T10:00'
    );
    await wrapper
      .get('input[type="datetime-local"]')
      .setValue('2026-11-04T11:30');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(execute.mock.calls[0][1].attributes).toEqual({
      begin: '2026-11-04 11:30:00',
      parent_id: 20,
    });
    wrapper.unmount();
  });
  it.each([
    ['Problem', 'problem.update', [1, 7, 2, 3, 4, 5, 8, 6]],
    ['Change', 'change.update', [1, 9, 10, 7, 4, 11, 12, 5, 8, 6, 14, 13]],
  ])(
    'uses the source status family for %s',
    (itemtype, operation, expected) => {
      const { wrapper } = render(
        descriptor({ itemtype, operation, fields: ['status'] }),
        { id: 5, entities_id: 0 }
      );
      expect(
        wrapper
          .findAll('select')
          .at(-1)
          .findAll('option')
          .slice(1)
          .map(option => Number(option.element.value))
      ).toEqual(expected);
      wrapper.unmount();
    }
  );
  it('offers urgency only through the source maximum five', () => {
    const { wrapper } = render(descriptor({ fields: ['urgency'] }), {
      id: 5,
      entities_id: 0,
    });
    expect(
      wrapper
        .findAll('select')
        .at(-1)
        .findAll('option')
        .slice(1)
        .map(option => Number(option.element.value))
    ).toEqual([1, 2, 3, 4, 5]);
    wrapper.unmount();
  });
  it('preserves a known root parent entity for a child operation without asking for a different entity', () => {
    const { wrapper } = render(
      descriptor({
        operation: 'followup.create',
        fields: ['content'],
        parent: 'Ticket',
        verb: 'post',
      }),
      null,
      20,
      0
    );
    const entity = wrapper.findAll('select')[1];
    expect(entity.element.value).toBe('0');
    expect(entity.attributes('disabled')).toBeDefined();
    wrapper.unmount();
  });
  it('sends a known parent revision for child creation without a child target', async () => {
    const { wrapper, execute } = render(
      descriptor({
        operation: 'followup.create',
        fields: ['content'],
        parent: 'Ticket',
        verb: 'post',
      }),
      null,
      20,
      0,
      '2026-11-04 10:00:00'
    );
    await wrapper.get('textarea').setValue('New followup');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(execute.mock.calls[0][1]).toMatchObject({
      target_id: null,
      attributes: { parent_id: 20 },
      expected_version: '2026-11-04 10:00:00',
    });
    wrapper.unmount();
  });
  it('does not reopen a historical command remote id under a different connection', async () => {
    const { wrapper, glpi } = render(descriptor(), {
      id: 20,
      entities_id: 0,
      title: 'Old',
    });
    glpi.binding = () => ({ connection_id: '9', connection_version: 1 });
    glpi.read.mockResolvedValue({
      command: {
        id: '81',
        state: 'succeeded',
        remote_id: 20,
        connection_id: '8',
        connection_version: 0,
      },
    });
    await wrapper.get('input[type="text"]').setValue('New title');
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(button => button.text() === messages.JRC_GLPI.check_send)
      .trigger('click');
    await flushPromises();
    expect(wrapper.emitted('succeeded')).toBeUndefined();
    expect(wrapper.text()).toContain(
      messages.JRC_GLPI.workspace.receipt_other_source
    );
    wrapper.unmount();
  });
  it('explains a denied source operation and cannot send it', () => {
    const { wrapper, execute } = render(descriptor({ source_allowed: false }));
    expect(wrapper.text()).toContain(
      messages.JRC_GLPI.workspace.blocks.source_denied
    );
    expect(wrapper.find('form').exists()).toBe(false);
    expect(execute).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
