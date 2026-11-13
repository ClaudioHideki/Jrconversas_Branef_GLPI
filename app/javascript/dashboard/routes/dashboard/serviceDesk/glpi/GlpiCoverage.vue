<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatGlpiDate } from './presentation';
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
    class="min-w-0 rounded-xl border p-3 text-sm"
    :class="
      status === 'complete'
        ? 'border-n-teal-6 bg-n-teal-2 text-n-teal-11'
        : status === 'partial'
          ? 'border-n-amber-6 bg-n-amber-2 text-n-amber-11'
          : 'border-n-weak bg-n-slate-2 text-n-slate-11'
    "
    role="status"
  >
    <details>
      <summary
        class="cursor-pointer font-semibold focus-visible:outline focus-visible:outline-2"
      >
        <span>{{ t(`JRC_GLPI.workspace.coverage.${status}`) }}</span>
        <span
          v-if="coverage?.collected_at || observedAt"
          class="ml-2 font-normal"
        >
          {{
            t('JRC_GLPI.visual.utc_timestamp', {
              time: formatGlpiDate(coverage?.collected_at || observedAt, 'UTC'),
            })
          }}
        </span>
      </summary>
      <p v-if="coverage?.observed_at || observedAt">
        {{
          t('JRC_GLPI.workspace.observed', {
            time: formatGlpiDate(coverage?.observed_at || observedAt, 'UTC'),
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
    </details>
  </div>
</template>
