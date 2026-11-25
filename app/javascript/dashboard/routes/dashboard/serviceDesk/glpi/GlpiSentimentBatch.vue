<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import GlpiTicketSentiment from './GlpiTicketSentiment.vue';
import { analysisReportHtml, analysisReportCsv } from './ticketAnalysisReport';
import { plainText } from './presentation';

const props = defineProps({
  glpi: { type: Object, required: true },
  filters: { type: Object, required: true },
  total: { type: Number, default: null },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['open']);
const { t } = useI18n();
const batch = ref(null);
const rows = ref(null);
const page = ref(1);
const detail = ref(null);
const heading = ref(null);
const exporting = ref(false);
const loading = ref(true);
let timer;
let disposed = false;
let generation = 0;
const base = 'sentiment/batches';
const active = computed(() =>
  ['queued', 'running', 'cancelling'].includes(batch.value?.state)
);
const busy = computed(
  () =>
    loading.value ||
    exporting.value ||
    props.glpi.state.loading.sentimentBatchAction
);
const errors = computed(() => props.glpi.state.errors);
const status = state => t(`JRC_GLPI.analysis.batch_state.${state}`);
const cards = [
  ['queued', 'bg-n-blue-3 text-n-blue-11'],
  ['running', 'bg-n-violet-3 text-n-violet-11'],
  ['analyzed', 'bg-n-teal-3 text-n-teal-11'],
  ['no_public_text', 'bg-n-amber-3 text-n-amber-11'],
  ['failed', 'bg-n-ruby-3 text-n-ruby-11'],
  ['cancelled', 'bg-n-slate-3 text-n-slate-11'],
];

const get = (key, path, params = {}) =>
  props.glpi.run(key, (account, signal) =>
    props.glpi.API.get(account, path, params, signal)
  );

const readRows = async (id, number, key = 'sentimentBatchRows') => {
  const data = await get(key, `${base}/${id}/rows`, { page: number });
  return data?.rows;
};

const openReport = async (number = 1, focus = true) => {
  const id = batch.value?.id;
  if (!id) return;
  const result = await readRows(id, number);
  if (!result || batch.value?.id !== id || disposed) return;
  rows.value = result;
  page.value = number;
  if (focus) {
    await nextTick();
    heading.value?.focus();
  }
};

const update = next => {
  const previous = batch.value;
  batch.value = next;
  if (previous?.id !== next?.id) {
    rows.value = null;
    detail.value = null;
  } else if (
    rows.value &&
    (previous?.state !== next?.state || previous?.processed !== next?.processed)
  ) {
    openReport(page.value, false);
  }
};

async function refresh() {
  clearTimeout(timer);
  const epoch = generation;
  const data = await get('sentimentBatch', base);
  if (disposed || epoch !== generation) return;
  if (data) update(data.batch);
  loading.value = false;
  if (active.value) timer = setTimeout(refresh, 5000);
}

const start = async () => {
  const epoch = generation;
  const data = await props.glpi.run('sentimentBatchAction', (account, signal) =>
    props.glpi.API.startSentimentBatch(account, props.filters, signal)
  );
  if (disposed || epoch !== generation) return;
  if (data?.batch) update(data.batch);
  await refresh();
};

const cancel = async () => {
  const id = batch.value.id;
  const data = await props.glpi.run('sentimentBatchAction', (account, signal) =>
    props.glpi.API.cancelSentimentBatch(account, id, signal)
  );
  if (!disposed && batch.value?.id === id && data?.batch) update(data.batch);
  await refresh();
};

const showDetail = async row => {
  detail.value = null;
  const id = batch.value.id;
  const data = await get(
    'sentimentBatchDetail',
    `${base}/${id}/rows/${row.ticket_id}`
  );
  if (!disposed && batch.value?.id === id && data?.analysis)
    detail.value = data.analysis;
};

const exportFailed = ref(false);
const download = async format => {
  const { id } = batch.value;
  exporting.value = true;
  exportFailed.value = false;
  try {
    const first = await readRows(id, 1, 'sentimentBatchExport');
    if (!first || batch.value?.id !== id || disposed) return;
    const items = [...first.items];
    for (
      let number = 2;
      number <= Math.ceil(first.total / first.per_page);
      number += 1
    ) {
      // Requests are ordered and every page is required before creating a file.
      // eslint-disable-next-line no-await-in-loop
      const result = await readRows(id, number, 'sentimentBatchExport');
      if (batch.value?.id !== id || disposed) return;
      if (!result || result.total !== first.total)
        throw new Error('Report changed');
      items.push(...result.items);
    }
    if (
      items.length !== first.total ||
      new Set(items.map(row => row.ticket_id)).size !== first.total
    ) {
      throw new Error('Report changed');
    }
    const isHtml = format === 'html';
    const content = isHtml
      ? analysisReportHtml(items, new Date().toISOString(), batch.value)
      : analysisReportCsv(items);
    const url = URL.createObjectURL(
      new Blob([content], {
        type: isHtml ? 'text/html;charset=utf-8' : 'text/csv;charset=utf-8',
      })
    );
    const link = document.createElement('a');
    link.href = url;
    link.download = `analise-glpi-lote-${id}.${format}`;
    link.click();
    URL.revokeObjectURL(url);
  } catch {
    exportFailed.value = true;
  } finally {
    exporting.value = false;
  }
};

watch(
  () => props.glpi.state.context,
  () => {
    generation += 1;
    clearTimeout(timer);
    batch.value = null;
    rows.value = null;
    detail.value = null;
    loading.value = true;
    refresh();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  disposed = true;
  clearTimeout(timer);
  [
    'sentimentBatch',
    'sentimentBatchRows',
    'sentimentBatchDetail',
    'sentimentBatchExport',
    'sentimentBatchAction',
  ].forEach(key => props.glpi.discard(key));
});
</script>

<template>
  <section
    class="grid min-w-0 gap-4 rounded-xl border border-n-blue-6 bg-n-solid-2 p-4"
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <h3 class="font-semibold">{{ t('JRC_GLPI.analysis.batch_heading') }}</h3>
      <div class="flex flex-wrap gap-2">
        <Button
          :label="t('JRC_GLPI.analysis.analyze_all', { count: total || 0 })"
          :disabled="disabled || busy || active || !total"
          @click="start"
        />
        <Button
          v-if="active"
          :label="t('JRC_GLPI.analysis.stop')"
          :disabled="busy || batch.state === 'cancelling'"
          variant="outline"
          @click="cancel"
        />
        <Button
          v-if="batch"
          :label="t('JRC_GLPI.analysis.batch_report')"
          variant="outline"
          @click="openReport()"
        />
      </div>
    </div>
    <p
      v-if="disabled"
      class="text-sm text-n-slate-11"
    >
      {{ t('JRC_GLPI.analysis.batch_coverage') }}
    </p>
    <p
      v-if="
        errors.sentimentBatchAction ||
        errors.sentimentBatch ||
        errors.sentimentBatchRows ||
        batch?.error
      "
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{
        t('JRC_GLPI.analysis.batch_error', {
          code:
            batch?.error ||
            errors.sentimentBatchAction?.code ||
            errors.sentimentBatchRows?.code ||
            errors.sentimentBatch?.code,
        })
      }}
      <Button
        v-if="errors.sentimentBatch"
        :label="t('JRC_GLPI.analysis.refresh_batch')"
        variant="ghost"
        @click="refresh"
      />
    </p>
    <template v-if="batch">
      <div class="flex flex-wrap items-center justify-between gap-2 text-sm">
        <span class="font-semibold">
          {{
            t('JRC_GLPI.analysis.batch_number', {
              id: batch.id,
              state: status(batch.state),
            })
          }}
        </span>
        <span v-if="batch.filters.from">
          {{
            t('JRC_GLPI.analysis.batch_period', {
              from: batch.filters.from,
              to: batch.filters.to,
            })
          }}
        </span>
        <span role="status">
          {{
            t('JRC_GLPI.analysis.progress', {
              done: batch.processed,
              total: batch.total,
            })
          }}
        </span>
      </div>
      <progress
        :value="batch.processed"
        :max="batch.total"
        :aria-label="t('JRC_GLPI.analysis.batch_progress')"
        class="h-2 w-full accent-n-blue-9"
      />
      <div class="grid grid-cols-2 gap-2 sm:grid-cols-3 xl:grid-cols-6">
        <div
          v-for="[state, color] in cards"
          :key="state"
          class="grid gap-1 rounded-lg p-3"
          :class="color"
        >
          <span class="text-sm">{{ status(state) }}</span>
          <strong class="text-xl tabular-nums">
            {{ batch.counts[state] || 0 }}
          </strong>
        </div>
      </div>
    </template>
    <section
      v-if="rows"
      class="grid gap-3"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h3
          ref="heading"
          tabindex="-1"
          class="font-semibold"
        >
          {{ t('JRC_GLPI.analysis.batch_report') }}
        </h3>
        <div class="flex gap-2">
          <Button
            :label="t('JRC_GLPI.analysis.download')"
            :disabled="exporting || active || !rows.total"
            @click="download('html')"
          />
          <Button
            :label="t('JRC_GLPI.analysis.export_csv')"
            :disabled="exporting || active || !rows.total"
            variant="outline"
            @click="download('csv')"
          />
        </div>
      </div>
      <p
        v-if="exportFailed || errors.sentimentBatchExport"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ t('JRC_GLPI.analysis.export_failed') }}
      </p>
      <p
        v-if="rows.total !== batch.total"
        class="text-sm text-n-amber-11"
      >
        {{
          t('JRC_GLPI.analysis.visible_batch_count', {
            count: rows.total,
            total: batch.total,
          })
        }}
      </p>
      <div class="overflow-x-auto rounded-xl border border-n-weak">
        <table class="w-full text-left text-sm">
          <thead class="bg-n-slate-2">
            <tr>
              <th class="p-3">{{ t('JRC_GLPI.id') }}</th>
              <th class="p-3">{{ t('JRC_GLPI.analysis.results') }}</th>
              <th class="p-3">{{ t('JRC_GLPI.sentiment.customer') }}</th>
              <th class="p-3">{{ t('JRC_GLPI.sentiment.operator') }}</th>
              <th class="p-3">{{ t('JRC_GLPI.analysis.actions') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in rows.items"
              :key="row.ticket_id"
              class="border-t border-n-weak"
            >
              <td class="p-3">
                #{{ row.ticket_id }} · {{ plainText(row.title) }}
              </td>
              <td class="p-3">
                <span
                  class="rounded-md px-2 py-1"
                  :class="cards.find(([key]) => key === row.status)?.[1]"
                >
                  {{ status(row.status) }}
                </span>
              </td>
              <td class="p-3">
                {{
                  row.report
                    ? t(
                        'JRC_GLPI.sentiment.labels.' +
                          row.report.customer_sentiment
                      )
                    : '—'
                }}
              </td>
              <td class="p-3">
                {{
                  row.report
                    ? t(
                        'JRC_GLPI.sentiment.labels.' +
                          row.report.agent_sentiment
                      )
                    : '—'
                }}
              </td>
              <td class="p-3">
                <Button
                  :label="t('JRC_GLPI.analysis.open')"
                  variant="ghost"
                  @click="emit('open', { id: row.ticket_id })"
                />
                <Button
                  v-if="row.report"
                  :label="t('JRC_GLPI.analysis.details')"
                  variant="outline"
                  @click="showDetail(row)"
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <Pagination
        v-if="rows.total > rows.per_page"
        :current-page="page"
        :total-items="rows.total"
        :items-per-page="rows.per_page"
        @update:current-page="openReport"
      />
      <p
        v-if="errors.sentimentBatchDetail"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ t('JRC_GLPI.analysis.detail_unavailable') }}
      </p>
      <section
        v-if="detail"
        class="grid gap-2"
      >
        <div class="flex items-center justify-between gap-2">
          <h3 class="font-semibold">
            #{{ detail.ticket_id }} · {{ plainText(detail.title) }}
          </h3>
          <Button
            :label="t('JRC_GLPI.analysis.close_detail')"
            variant="ghost"
            @click="detail = null"
          />
        </div>
        <GlpiTicketSentiment
          :key="detail.ticket_id"
          :ticket-id="detail.ticket_id"
          :glpi="glpi"
          :saved-analysis="detail"
          read-only
        />
      </section>
    </section>
  </section>
</template>
