import { mount } from '@vue/test-utils';
import { describe, expect, it } from 'vitest';
import { createI18n } from 'vue-i18n';
import Coverage from './GlpiCoverage.vue';
import messages from 'dashboard/i18n/locale/en/jrcGlpi.json';

describe('source coverage diagnostics', () => {
  it.each([
    [{ ERROR_RIGHT_MISSING: 2 }, 'ERROR_RIGHT_MISSING', '2'],
    [
      { 0: { code: 'ERROR_RIGHT_MISSING' }, 7: 'ERROR_NOT_FOUND' },
      'ERROR_NOT_FOUND',
      '1',
    ],
  ])('renders source codes and counts for %j', (errors, code, count) => {
    const wrapper = mount(Coverage, {
      props: { coverage: { complete: false, errors } },
      global: {
        plugins: [
          createI18n({
            legacy: false,
            locale: 'en',
            messages: { en: messages },
          }),
        ],
      },
    });
    expect(wrapper.text()).toContain(code);
    expect(wrapper.text()).toContain(`(${count})`);
  });
});
