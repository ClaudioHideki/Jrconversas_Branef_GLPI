<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { serviceDeskRouteName } from '../routeDefinitions';
import {
  analysisReportHtml,
  analysisReportCsv,
  countAnalysisResults,
} from './ticketAnalysisReport';
import Button from 'dashboard/components-next/button/Button.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import GlpiFilters from './GlpiFilters.vue';
import GlpiCoverage from './GlpiCoverage.vue';
import GlpiBadge from './GlpiBadge.vue';
import GlpiSentimentBatch from './GlpiSentimentBatch.vue';
import GlpiTicketSentiment from './GlpiTicketSentiment.vue';
import { analysisPeriod } from './analysisPeriod';
import { plainText, selectedFilters } from './presentation';

const props = defineProps({
  glpi: { type: Object, required: true },
  initialFilters: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['filters']);
const { t } = useI18n();
const router = useRouter();
const selectedIds = ref([]);
const reports = ref({});
const batch = ref(false);
const processed = ref(0);
const batchTotal = ref(0);
const stopRequested = ref(false);
let disposed = false;
let scopeGeneration = 0;
const reportRows = computed(() =>
  Object.values(reports.value).sort(
    (a, b) => Number(a.ticket_id) - Number(b.ticket_id)
  )
);
const reportCounts = computed(() => countAnalysisResults(reportRows.value));
const selected = ref(null);
const reportHeading = ref(null);
const detailHeading = ref(null);
const list = computed(() => props.glpi.state.data.analysisTickets);
const choose = async (ticket, select = true) => {
  if (batch.value) return;
  selected.value = ticket;
  if (select && !selectedIds.value.includes(ticket.id))
    selectedIds.value.push(ticket.id);
  await nextTick();
  detailHeading.value?.focus();
};
const remember = (value, ticket = selected.value) => {
  if (ticket && String(value.ticket_id) === String(ticket.id))
    reports.value[ticket.id] = { ...value, title: plainText(ticket.title) };
};
const open = ticket =>
  router.push({
    name: serviceDeskRouteName('detail'),
    params: {
      accountId: props.glpi.session.accountId.value,
      ticketId: ticket.id,
    },
  });
const analyzeSelection = async () => {
  if (batch.value || !selectedIds.value.length) return;
  batch.value = true;
  stopRequested.value = false;
  processed.value = 0;
  const epoch = scopeGeneration;
  const tickets = (list.value?.items || []).filter(ticket =>
    selectedIds.value.includes(ticket.id)
  );
  batchTotal.value = tickets.length;
  try {
    await tickets.reduce(async (previous, ticket) => {
      await previous;
      if (disposed || stopRequested.value || epoch !== scopeGeneration) return;
      if (!reports.value[ticket.id]) {
        const key = `sentiment:${ticket.id}`;
        const data = await props.glpi.run(key, (account, signal) =>
          props.glpi.API.analyzeSentiment(
            account,
            String(ticket.id),
            { scope: 'ticket' },
            signal
          )
        );
        if (disposed || epoch !== scopeGeneration) return;
        if (String(data?.analysis?.ticket_id) === String(ticket.id))
          remember(data.analysis, ticket);
        else
          reports.value[ticket.id] = {
            ticket_id: ticket.id,
            title: plainText(ticket.title),
            status: 'failed',
            error: props.glpi.state.errors[key]?.code || 'unavailable',
          };
      }
      processed.value += 1;
    }, Promise.resolve());
  } finally {
    batch.value = false;
  }
};
const download = format => {
  if (!reportRows.value.length) return;
  const html = format === 'html';
  const url = URL.createObjectURL(
    new Blob(
      [
        html
          ? analysisReportHtml(reportRows.value)
          : analysisReportCsv(reportRows.value),
      ],
      { type: html ? 'text/html;charset=utf-8' : 'text/csv;charset=utf-8' }
    )
  );
  const link = document.createElement('a');
  link.href = url;
  link.download = `analise-chamados-glpi.${format}`;
  link.click();
  URL.revokeObjectURL(url);
};
const filters = ref(selectedFilters(props.initialFilters));
const page = ref(1);
const pending = computed(() => props.glpi.state.loading.analysisTickets);
const period = computed(() =>
  analysisPeriod(filters.value.from, filters.value.to)
);
const invalid = computed(
  () => !!(filters.value.from || filters.value.to) && !period.value
);
const batchFilters = computed(() => {
  const { from, to, ...rest } = filters.value;
  return { ...rest, ...(period.value || {}) };
});
const load = () => {
  selected.value = null;
  selectedIds.value = [];
  props.glpi.discard('analysisTickets');
  if (invalid.value) return;
  const { from, to, ...rest } = filters.value;
  props.glpi.read(
    'analysisTickets',
    period.value ? 'sentiment/candidates' : 'tickets',
    {
      ...rest,
      ...(period.value || {}),
      page: page.value,
      per_page: 25,
    }
  );
};
const apply = values => {
  filters.value = values;
  page.value = 1;
  emit('filters', values);
  load();
};
watch(
  () => props.initialFilters,
  query => {
    const next = selectedFilters(query);
    if (JSON.stringify(next) !== JSON.stringify(filters.value)) {
      filters.value = next;
      page.value = 1;
      load();
    }
  },
  { deep: true }
);
watch(
  () => props.glpi.state.context,
  () => {
    selected.value = null;
    selectedIds.value = [];
    reports.value = {};
    stopRequested.value = true;
    scopeGeneration += 1;
  }
);
load();
onBeforeUnmount(() => {
  disposed = true;
  stopRequested.value = true;
  props.glpi.discard('analysisTickets');
});
</script>

<template>
  <section
    class="grid min-w-0 gap-4"
    data-testid="glpi-ticket-analysis"
  >
    <p class="text-sm text-n-slate-11">{{ t('JRC_GLPI.analysis.scope') }}</p>
    <GlpiFilters
      :entities="glpi.state.context.entities"
      :busy="pending || batch"
      :initial-filters="filters"
      analysis-period
      @apply="apply"
    />
    <p
      v-if="invalid"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('JRC_GLPI.sentiment.invalid_period') }}
    </p>
    <p
      v-if="pending"
      role="status"
    >
      {{ t('JRC_GLPI.loading') }}
    </p>
    <GlpiSentimentBatch
      v-if="glpi.state.context.can_analyze_batch"
      :glpi="glpi"
      :filters="batchFilters"
      :total="list?.meta.total ?? null"
      :disabled="pending || invalid || list?.coverage.state !== 'complete'"
      @open="open"
    />
    <div class="flex flex-wrap items-center gap-3">
      <Button
        :label="
          t('JRC_GLPI.analysis.analyze_selected', { count: selectedIds.length })
        "
        :disabled="batch || !selectedIds.length"
        @click="analyzeSelection"
      />
      <Button
        v-if="batch"
        :label="t('JRC_GLPI.analysis.stop')"
        variant="outline"
        @click="stopRequested = true"
      />
      <span
        v-if="batch"
        role="status"
      >
        {{
          t('JRC_GLPI.analysis.progress', {
            done: processed,
            total: batchTotal,
          })
        }}
      </span>
      <Button
        v-if="reportRows.length"
        :label="
          t('JRC_GLPI.analysis.view_report', { count: reportRows.length })
        "
        variant="outline"
        @click="reportHeading?.focus()"
      />
    </div>
    <progress
      v-if="batch && batchTotal"
      :value="processed"
      :max="batchTotal"
      :aria-label="t('JRC_GLPI.analysis.batch_progress')"
      class="h-2 w-full accent-n-blue-9"
    />
    <template v-if="list">
      <GlpiCoverage
        :coverage="list.coverage"
        :observed-at="list.observed_at || ''"
      />
      <p class="text-sm font-semibold">
        {{
          list.meta.total == null
            ? t('JRC_GLPI.visual.unavailable_total')
            : t('JRC_GLPI.visible_total', { count: list.meta.total })
        }}
      </p>
      <div
        class="min-w-0 overflow-x-auto rounded-xl border border-n-weak bg-n-solid-2"
      >
        <table class="w-full text-left text-sm">
          <thead class="bg-n-slate-2">
            <tr>
              <th class="p-3">
                <input
                  type="checkbox"
                  :aria-label="t('JRC_GLPI.analysis.select_page')"
                  :disabled="batch"
                  :checked="
                    !!list.items.length &&
                    selectedIds.length === list.items.length
                  "
                  @change="
                    selectedIds = $event.target.checked
                      ? list.items.map(ticket => ticket.id)
                      : []
                  "
                />
              </th>
              <th
                v-for="field in ['id', 'title', 'entity', 'status', 'priority']"
                :key="field"
                class="p-3"
              >
                {{ t(`JRC_GLPI.${field}`) }}
              </th>
              <th class="p-3">{{ t('JRC_GLPI.analysis.select') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="ticket in list.items"
              :key="ticket.id"
              class="border-t border-n-weak"
            >
              <td class="p-3">
                <input
                  v-model="selectedIds"
                  type="checkbox"
                  :value="ticket.id"
                  :aria-label="
                    t('JRC_GLPI.analysis.select_number', { id: ticket.id })
                  "
                  :disabled="batch"
                />
              </td>
              <td class="p-3">#{{ ticket.id }}</td>
              <td class="p-3">{{ plainText(ticket.title) }}</td>
              <td class="p-3">
                {{
                  plainText(
                    ticket.entity ||
                      glpi.state.context.entities?.find(
                        entity =>
                          String(entity.id) === String(ticket.entities_id)
                      )?.name
                  )
                }}
              </td>
              <td class="p-3">
                <GlpiBadge
                  kind="status"
                  :value="ticket.status"
                />
              </td>
              <td class="p-3">
                <GlpiBadge
                  kind="priority"
                  :value="ticket.priority"
                />
              </td>
              <td class="p-3">
                <Button
                  :label="t('JRC_GLPI.analysis.select')"
                  variant="outline"
                  :disabled="batch"
                  @click="choose(ticket)"
                />
                <Button
                  :label="t('JRC_GLPI.analysis.open')"
                  variant="ghost"
                  @click="open(ticket)"
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-if="!list.items.length && list.meta.total != null">
        {{ t('JRC_GLPI.empty') }}
      </p>
      <Pagination
        v-if="list.meta.total"
        :current-page="page"
        :total-items="list.meta.total"
        :items-per-page="25"
        @update:current-page="
          page = $event;
          load();
        "
      />
    </template>
    <section
      v-if="reportRows.length"
      class="grid gap-3"
      data-testid="analysis-report-list"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h3
            ref="reportHeading"
            tabindex="-1"
            class="font-semibold"
          >
            {{ t('JRC_GLPI.analysis.results') }}
          </h3>
          <p class="text-sm text-n-slate-11">
            {{ t('JRC_GLPI.analysis.session_report') }}
          </p>
        </div>
        <div class="flex flex-wrap gap-2">
          <Button
            :label="t('JRC_GLPI.analysis.download')"
            :disabled="batch"
            @click="download('html')"
          />
          <Button
            :label="t('JRC_GLPI.analysis.export_csv')"
            :disabled="batch"
            variant="outline"
            @click="download('csv')"
          />
          <Button
            :label="t('JRC_GLPI.analysis.clear')"
            :disabled="batch"
            variant="ghost"
            @click="reports = {}"
          />
        </div>
      </div>
      <div class="flex flex-wrap gap-2 text-sm">
        <span class="rounded-lg bg-n-teal-3 px-3 py-2 text-n-teal-11">
          {{
            t('JRC_GLPI.analysis.result_count', {
              count: reportCounts.analyzed,
            })
          }}
        </span>
        <span class="rounded-lg bg-n-amber-3 px-3 py-2 text-n-amber-11">
          {{
            t('JRC_GLPI.analysis.empty_count', { count: reportCounts.empty })
          }}
        </span>
        <span class="rounded-lg bg-n-ruby-3 px-3 py-2 text-n-ruby-11">
          {{
            t('JRC_GLPI.analysis.failed_count', { count: reportCounts.failed })
          }}
        </span>
      </div>
      <article
        v-for="row in reportRows"
        :key="row.ticket_id"
        class="rounded-xl border border-n-weak p-3 text-sm"
      >
        <p class="font-semibold">#{{ row.ticket_id }} · {{ row.title }}</p>
        <p v-if="!row.report">
          {{
            row.status === 'no_public_text'
              ? t('JRC_GLPI.sentiment.no_text')
              : t('JRC_GLPI.sentiment.failed')
          }}
        </p>
        <p v-if="row.report">
          {{ t('JRC_GLPI.sentiment.customer') }}:
          {{ t('JRC_GLPI.sentiment.labels.' + row.report.customer_sentiment) }}
          · {{ t('JRC_GLPI.sentiment.operator') }}:
          {{ t('JRC_GLPI.sentiment.labels.' + row.report.agent_sentiment) }}
        </p>
        <p v-if="row.usage">
          {{
            t('JRC_GLPI.sentiment.tokens', {
              input: row.usage.input_tokens,
              output: row.usage.output_tokens,
              total: row.usage.total_tokens,
            })
          }}
        </p>
        <Button
          :label="t('JRC_GLPI.analysis.open')"
          variant="ghost"
          @click="open({ id: row.ticket_id })"
        />
        <Button
          :label="t('JRC_GLPI.analysis.details')"
          :disabled="batch"
          variant="outline"
          @click="choose({ id: row.ticket_id, title: row.title }, false)"
        />
      </article>
    </section>
    <section
      v-if="selected"
      class="grid gap-3"
      data-testid="selected-analysis-ticket"
    >
      <h3
        ref="detailHeading"
        tabindex="-1"
        class="font-semibold"
      >
        #{{ selected.id }} · {{ plainText(selected.title) }}
      </h3>
      <GlpiTicketSentiment
        :key="selected.id"
        :glpi="glpi"
        :ticket-id="selected.id"
        :saved-analysis="reports[selected.id] || null"
        @completed="remember"
      />
    </section>
  </section>
</template>
