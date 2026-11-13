import { mount } from '@vue/test-utils';
import GlpiFilters from './GlpiFilters.vue';

describe('applied GLPI filters', () => {
  it('applies, removes and clears actual query parameters rather than only hiding chips', async () => {
    const wrapper = mount(GlpiFilters, {
      props: { initialFilters: { search: '6693', status: '4' } },
    });
    expect(wrapper.find('input[maxlength]').element.value).toBe('6693');
    await wrapper.find('form').trigger('submit');
    expect(wrapper.emitted('apply').at(-1)[0]).toEqual({
      search: '6693',
      status: '4',
    });
    await wrapper.find('[data-filter="status"]').trigger('click');
    expect(wrapper.emitted('apply').at(-1)[0]).toEqual({ search: '6693' });
    await wrapper.find('[data-testid="clear-filters"]').trigger('click');
    expect(wrapper.emitted('apply').at(-1)[0]).toEqual({});
  });
});
