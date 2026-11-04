import { describe, expect, it } from 'vitest';
import { mount } from '@vue/test-utils';
import Editor from './GlpiRichEditor.vue';

describe('GLPI rich content editor', () => {
  it('preserves tables and safe links and prevents embedded remote media', () => {
    const wrapper = mount(Editor, {
      props: {
        label: 'Content',
        modelValue:
          '<p><a href="https://example.test/article">Reference</a></p><table><tbody><tr><td>Cell A</td><td>Cell B</td></tr></tbody></table><img src="https://example.test/private.png"><iframe src="https://example.test/private"></iframe>',
      },
    });
    expect(wrapper.findAll('td').map(cell => cell.text())).toEqual([
      'Cell A',
      'Cell B',
    ]);
    expect(wrapper.get('a[href="https://example.test/article"]').text()).toBe(
      'Reference'
    );
    expect(wrapper.find('img, iframe').exists()).toBe(false);
    expect(wrapper.get('[role="textbox"]').attributes('aria-label')).toBe(
      'Content'
    );
    wrapper.unmount();
  });
  it('makes confirmed or sending content read only', () => {
    const wrapper = mount(Editor, {
      props: {
        label: 'Content',
        modelValue: '<p>Existing</p>',
        disabled: true,
      },
    });
    expect(wrapper.get('[role="textbox"]').attributes('contenteditable')).toBe(
      'false'
    );
    wrapper.unmount();
  });
});
