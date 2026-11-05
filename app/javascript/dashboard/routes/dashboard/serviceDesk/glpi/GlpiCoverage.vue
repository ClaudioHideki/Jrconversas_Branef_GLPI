<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
const props = defineProps({
  coverage: { type: Object, default: null },
  observedAt: { type: String, default: '' },
});
const { t } = useI18n();
const errors = computed(() => {
  const counts = {};
  Object.entries(props.coverage?.errors || {}).forEach(([key, value]) => {
    let code = value?.code;
    if (typeof value === 'number') code = key;
    if (typeof value === 'string') code = value;
    if (code)
      counts[code] =
        (counts[code] || 0) + (typeof value === 'number' ? value : 1);
  });
  return Object.entries(counts).map(([code, count]) => ({ code, count }));
});
const status = computed(() => {
  if (props.coverage?.state) return props.coverage.state;
  if (props.coverage?.complete === true) return 'complete';
  if (props.coverage?.complete === false) return 'partial';
  return 'unavailable';
});
</script>

<template>
  <div
    class="grid gap-1 rounded-lg border border-n-weak bg-n-slate-2 p-3 text-xs"
    role="status"
  >
    <p>{{ t(`JRC_GLPI.workspace.coverage.${status}`) }}</p>
    <p v-if="coverage?.observed_at || observedAt">
      {{
        t('JRC_GLPI.workspace.observed', {
          time: coverage?.observed_at || observedAt,
        })
      }}
    </p>
    <p>{{ t('JRC_GLPI.workspace.non_atomic') }}</p>
    <p
      v-for="error in errors"
      :key="error.code"
    >
      {{
        t('JRC_GLPI.source_code', {
          code: error.code,
        })
      }}
      ({{ error.count }})
    </p>
  </div>
</template>
