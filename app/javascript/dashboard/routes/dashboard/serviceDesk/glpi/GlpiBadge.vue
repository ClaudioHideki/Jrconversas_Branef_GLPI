<script setup>
import { useI18n } from 'vue-i18n';
import { badgeTone } from './presentation';
defineProps({
  kind: { type: String, required: true },
  value: { type: [String, Number], default: '' },
});
const { t } = useI18n();
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full border px-2.5 py-1 text-xs font-semibold"
    :class="badgeTone(kind, value)"
  >
    <span
      class="size-1.5 rounded-full bg-current"
      aria-hidden="true"
    />
    {{
      [1, 2, 3, 4, 5, 6].includes(Number(value))
        ? t(
            `JRC_GLPI.${kind === 'status' ? 'statuses' : 'priorities'}.${value}`
          )
        : t('JRC_GLPI.unclassified')
    }}
  </span>
</template>
