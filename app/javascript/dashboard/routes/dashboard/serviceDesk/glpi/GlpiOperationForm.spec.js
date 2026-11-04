import { describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createI18n } from 'vue-i18n';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';
import serviceMessages from 'dashboard/i18n/locale/en/jrcServiceDesk.json';
import Form from './GlpiOperationForm.vue';

const render = (operation, record = null, parentId = null) => {
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
    props: { glpi, operations: [operation], record, parentId },
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
