<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import GlpiBadge from './GlpiBadge.vue';
import { plainText, selectedFilters } from './presentation';
import Button from 'dashboard/components-next/button/Button.vue';
import GlpiCoverage from './GlpiCoverage.vue';
import GlpiFilters from './GlpiFilters.vue';
import GlpiResourceBoard from './GlpiResourceBoard.vue';
const props = defineProps({
  glpi: { type: Object, required: true },
  screen: { type: String, default: 'overview' },
  initialFilters: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['filters']);
const { t } = useI18n();
const filters = ref(selectedFilters(props.initialFilters));

const dimensionLabel = (dimension, value) => {
  if (value === 'unclassified') return t('JRC_GLPI.unclassified');
  if (dimension === 'by_entity')
    return plainText(
      props.glpi.state.context.entities?.find(
        entity => String(entity.id) === String(value)
      )?.name || t('JRC_GLPI.entity_number', { id: value })
    );
  if (dimension === 'by_technician' && /^\d+$/.test(value))
    return t('JRC_GLPI.visual.catalog_id', { id: value });
  return plainText(value);
};
const metricTone = metric =>
  ({
    total: 'border-n-blue-6 bg-n-blue-2 text-n-blue-11',
    with_deadline: 'border-n-teal-6 bg-n-teal-2 text-n-teal-11',
    exceeded: 'border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11',
    without_deadline: 'border-n-amber-6 bg-n-amber-2 text-n-amber-11',
  })[metric];
const report = computed(() => props.glpi.state.data.overview?.report);
const receipt = computed(() => props.glpi.state.data.export?.export);
const requestedFilters = ref(null);
const exportFilters = computed(
  () => receipt.value?.filters || requestedFilters.value
);
const filterLabels = {
  entity_id: 'entity',
  status: 'status',
  priority: 'priority',
  search: 'workspace.search',
  from: 'from',
  to: 'to',
  type: 'type',
  mine: 'workspace.my_queue',
};
const filterValue = (field, value) => {
  if (field === 'entity_id')
    return (
      props.glpi.state.context.entities.find(
        row => String(row.id) === String(value)
      )?.name || t('JRC_GLPI.entity_number', { id: value })
    );
  if (field === 'status') return t(`JRC_GLPI.statuses.${value}`);
  if (field === 'priority') return t(`JRC_GLPI.priorities.${value}`);
  if (field === 'type')
    return t(
      value === 1 || value === '1' ? 'JRC_GLPI.incident' : 'JRC_GLPI.request'
    );
  if (field === 'mine') return t('JRC_GLPI.choices.yes');
  return value;
};
const downloadRequested = ref(false);
let timer;
let disposed = false;
onBeforeUnmount(() => {
  disposed = true;
  clearTimeout(timer);
});
const load = () => props.glpi.read('overview', 'overview', filters.value);
const applyFilters = values => {
  filters.value = values;
  emit('filters', values);
  load();
};
watch(
  () => props.initialFilters,
  query => {
    const next = selectedFilters(query);
    if (JSON.stringify(next) === JSON.stringify(filters.value)) return;
    filters.value = next;
    load();
  },
  { deep: true }
);
const download = async () => {
  if (!receipt.value || receipt.value.state !== 'ready') return;
  const id = receipt.value.id;
  const result = await props.glpi.run(
    'export',
    (account, signal) => props.glpi.API.downloadExport(account, id, signal),
    { binary: true, maxBytes: Infinity }
  );
  if (result?.binary) {
    downloadRequested.value = false;
    const url = URL.createObjectURL(result.binary);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'glpi-tickets.csv';
    link.click();
    URL.revokeObjectURL(url);
    await props.glpi.read('export', `exports/${id}`);
  }
};
const poll = async () => {
  if (disposed || !receipt.value) return;
  await props.glpi.read('export', `exports/${receipt.value.id}`);
  if (disposed) return;
  if (
    downloadRequested.value &&
    receipt.value?.can_download &&
    receipt.value.state === 'ready'
  )
    await download();
  if (['queued', 'running', 'verifying'].includes(receipt.value?.state))
    timer = setTimeout(poll, 2000);
};
const start = async () => {
  downloadRequested.value = false;
  const snapshot = { ...filters.value };
  const result = await props.glpi.run('export', (account, signal) =>
    props.glpi.API.startExport(account, snapshot, signal)
  );
  if (result?.export) {
    requestedFilters.value = snapshot;
    timer = setTimeout(poll, 2000);
  }
};
const requestDownload = async () => {
  downloadRequested.value = true;
  await download();
  if (receipt.value?.state === 'verifying') timer = setTimeout(poll, 2000);
};
const cancel = async () => {
  clearTimeout(timer);
  downloadRequested.value = false;
  await props.glpi.run('export', (account, signal) =>
    props.glpi.API.cancelExport(account, receipt.value.id, signal)
  );
};
load();
</script>

<template>
  <section
    class="grid gap-4"
    data-testid="glpi-overview"
  >
    <GlpiFilters
      :entities="glpi.state.context.entities"
      :busy="glpi.state.loading.overview"
      :initial-filters="filters"
      @apply="applyFilters"
    />
    <p
      v-if="glpi.state.loading.overview"
      role="status"
    >
      {{ t('JRC_GLPI.loading') }}
    </p>
    <template v-if="report">
      <GlpiCoverage
        :coverage="report.coverage"
        :observed-at="report.observed_at || report.generated_at || ''"
      />
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <article
          v-for="(value, metric) in {
            total: report.total,
            with_deadline: report.solution_sla?.with_deadline,
            exceeded: report.solution_sla?.exceeded,
            without_deadline: report.solution_sla?.without_deadline,
          }"
          :key="metric"
          class="min-w-0 rounded-2xl border bg-n-solid-2 p-5 shadow-sm"
          :class="metricTone(metric)"
        >
          <h3 class="text-sm text-n-slate-11">
            {{ t(`JRC_GLPI.metrics.${metric}`) }}
          </h3>
          <p class="mt-2 text-3xl font-semibold">
            {{
              report.total == null
                ? t('JRC_GLPI.workspace.unavailable_value')
                : (value ?? t('JRC_GLPI.workspace.unavailable_value'))
            }}
          </p>
        </article>
      </div>
      <div class="grid gap-3 md:grid-cols-2">
        <article
          v-for="dimension in [
            'by_status',
            'by_priority',
            'by_entity',
            'by_opening_year',
            'by_technician',
          ]"
          :key="dimension"
          class="min-w-0 rounded-2xl border bg-n-solid-2 p-5 shadow-sm"
        >
          <h3
            class="mb-4 flex items-center gap-2 text-base font-bold text-n-slate-12"
          >
            <i
              class="i-lucide-chart-no-axes-combined size-4 text-n-blue-11"
              aria-hidden="true"
            />
            {{ t(`JRC_GLPI.${dimension}`) }}
          </h3>
          <dl class="grid gap-2">
            <div
              v-for="(count, label) in report[dimension] || {}"
              :key="label"
              class="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-n-slate-2 px-3 py-2 text-sm"
            >
              <dt>
                <GlpiBadge
                  v-if="
                    dimension === 'by_status' || dimension === 'by_priority'
                  "
                  :kind="dimension === 'by_status' ? 'status' : 'priority'"
                  :value="label"
                />
                <span v-else>{{ dimensionLabel(dimension, label) }}</span>
              </dt>
              <dd class="font-bold text-n-slate-12">{{ count }}</dd>
              <progress
                :value="count"
                :max="Math.max(1, report.total || 0)"
                class="h-1.5 w-full appearance-none overflow-hidden rounded-full [&::-webkit-progress-bar]:bg-n-slate-4 [&::-webkit-progress-value]:bg-n-blue-9 [&::-moz-progress-bar]:bg-n-blue-9"
                :aria-label="`${dimensionLabel(dimension, label)}: ${count}`"
              />
            </div>
          </dl>
        </article>
      </div>
      <p class="text-xs text-n-slate-11">{{ t('JRC_GLPI.report_scope') }}</p>
    </template>
    <template v-if="screen === 'sla'">
      <GlpiResourceBoard
        :glpi="glpi"
        resource="sla"
      />
      <GlpiResourceBoard
        :glpi="glpi"
        resource="calendars"
      />
    </template>
    <section
      v-if="glpi.state.context.can_export"
      class="grid min-w-0 gap-4 rounded-2xl border border-n-blue-6 bg-n-solid-2 p-5 shadow-sm"
    >
      <h3 class="font-semibold">
        {{ t('JRC_GLPI.workspace.export_heading') }}
      </h3>
      <Button
        type="button"
        :label="t('JRC_SERVICE_DESK.COMMON.export')"
        :disabled="
          glpi.state.loading.export ||
          ['queued', 'running', 'verifying'].includes(receipt?.state)
        "
        @click="start"
      />
      <template v-if="receipt">
        <section class="grid gap-2 rounded-lg bg-n-slate-2 p-3 text-xs">
          <h4 class="font-semibold">
            {{ t('JRC_GLPI.workspace.export_filter_scope') }}
          </h4>
          <p v-if="!exportFilters">
            {{ t('JRC_GLPI.workspace.export_scope_unknown') }}
          </p>
          <p v-else-if="!Object.keys(exportFilters).length">
            {{ t('JRC_GLPI.workspace.export_scope_all') }}
          </p>
          <dl
            v-if="exportFilters"
            class="grid gap-1"
          >
            <div
              v-for="(value, field) in exportFilters"
              :key="field"
            >
              <template v-if="filterLabels[field]">
                <dt class="font-medium">
                  {{ t(`JRC_GLPI.${filterLabels[field]}`) }}
                </dt>
                <dd>{{ filterValue(field, value) }}</dd>
              </template>
            </div>
          </dl>
        </section>
        <p role="status">
          {{
            t('JRC_GLPI.workspace.export_progress', {
              state: t(`JRC_GLPI.exports.${receipt.state}`),
              processed: receipt.processed,
              total: receipt.total ?? t('JRC_GLPI.workspace.unavailable_value'),
            })
          }}
        </p>
        <progress
          v-if="receipt.total"
          class="w-full"
          :max="receipt.total"
          :value="receipt.processed"
          :aria-label="t('JRC_GLPI.workspace.export_heading')"
        />
        <GlpiCoverage :coverage="receipt.coverage" />
        <p
          v-if="receipt.error_code"
          role="alert"
        >
          {{ t('JRC_GLPI.source_code', { code: receipt.error_code }) }}
        </p>
        <p
          v-if="receipt.verified_from"
          class="text-xs"
        >
          {{
            t('JRC_GLPI.workspace.verified_interval', {
              from: receipt.verified_from,
              to: receipt.verified_until,
            })
          }}
        </p>
        <Button
          v-if="receipt.state === 'ready'"
          type="button"
          :label="t('JRC_GLPI.workspace.download')"
          :disabled="glpi.state.loading.export"
          @click="requestDownload"
        />
        <Button
          v-if="['queued', 'running', 'verifying'].includes(receipt.state)"
          type="button"
          variant="outline"
          :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
          @click="cancel"
        />
      </template>
    </section>
  </section>
</template>
