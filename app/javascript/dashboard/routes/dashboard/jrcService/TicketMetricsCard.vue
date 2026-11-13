<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
const props = defineProps({ metrics: { type: Object, required: true } });
const emit = defineEmits(['navigate']);
const { t } = useI18n();
const available = computed(() =>
  ['complete', 'partial'].includes(props.metrics.state)
);
const collected = computed(() =>
  props.metrics.collected_at
    ? new Intl.DateTimeFormat('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
        timeZone: props.metrics.timezone || 'UTC',
      }).format(new Date(props.metrics.collected_at))
    : '—'
);
const navigate = () => {
  if (props.metrics.route_name)
    emit('navigate', {
      name: props.metrics.route_name,
      query: props.metrics.filters,
    });
};
</script>

<template>
  <button
    type="button"
    class="min-w-0 rounded-2xl border border-n-blue-6 bg-n-blue-2 p-4 text-left shadow-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
    :disabled="!metrics.route_name"
    @click="navigate"
  >
    <span
      class="flex items-center justify-between gap-3 text-sm font-semibold text-n-blue-11"
    >
      {{ t('JRC_COCKPIT_TICKETS.title', { source: metrics.source }) }}
      <i class="i-lucide-ticket size-5" aria-hidden="true" />
    </span>
    <strong
      data-testid="ticket-total"
      class="my-2 block text-3xl text-n-slate-12"
      >{{ available && metrics.total != null ? metrics.total : '—' }}</strong
    >
    <span
      class="block text-sm font-medium"
      :class="
        metrics.state === 'partial' ? 'text-n-amber-11' : 'text-n-slate-11'
      "
      role="status"
      >{{ t(`JRC_COCKPIT_TICKETS.${metrics.state}`) }}</span
    >
    <span
      v-if="available && metrics.active != null"
      class="mt-1 block text-xs text-n-slate-11"
      >{{ t('JRC_COCKPIT_TICKETS.active', { count: metrics.active }) }} ·
      {{ t('JRC_COCKPIT_TICKETS.exceeded', { count: metrics.exceeded }) }}</span
    >
    <span
      v-if="metrics.filters?.from"
      class="mt-2 block text-xs text-n-slate-11"
      >{{ t('JRC_COCKPIT_TICKETS.scope', metrics.filters) }}</span
    >
    <span class="mt-1 block text-xs text-n-slate-11">{{
      t('JRC_COCKPIT_TICKETS.collected', {
        time: collected,
        timezone: metrics.timezone || 'UTC',
      })
    }}</span>
  </button>
</template>
