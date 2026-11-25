<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { canRead, canonicalId } from '../helpers/access';
import { analysisPeriod } from './analysisPeriod';
import { analysisReportHtml } from './ticketAnalysisReport';
import { formatGlpiDate } from './presentation';

const props = defineProps({
  readOnly: { type: Boolean, default: false },
  wholeTicket: { type: Boolean, default: true },
  savedAnalysis: { type: Object, default: null },
  initialFrom: { type: String, default: '' },
  initialThrough: { type: String, default: '' },
  glpi: { type: Object, required: true },
  ticketId: { type: [String, Number], required: true },
});
const emit = defineEmits(['completed']);
const { t } = useI18n();
const from = ref(props.initialFrom);
const through = ref(props.initialThrough);
const key = computed(() => `sentiment:${canonicalId(props.ticketId)}`);
const permitted = computed(() =>
  canRead(props.glpi.session.state.context, 'reports')
);
const pending = computed(() => props.glpi.state.loading[key.value] === true);
const analysis = computed(() => {
  const value = props.readOnly
    ? props.savedAnalysis
    : props.glpi.state.data[key.value]?.analysis || props.savedAnalysis;
  return canonicalId(value?.ticket_id) === canonicalId(props.ticketId)
    ? value
    : null;
});
const report = computed(() => analysis.value?.report);
const score = computed(() =>
  report.value?.quality_score == null
    ? t('JRC_GLPI.sentiment.unavailable')
    : t('JRC_GLPI.sentiment.score_value', {
        score: report.value.quality_score,
      })
);
const sections = ['summary', 'quality', 'audit', 'evidence'];
const section = ref('summary');
watch(analysis, () => {
  section.value = 'summary';
});
const error = computed(() => props.glpi.state.errors[key.value]);
const period = computed(() =>
  props.wholeTicket
    ? { scope: 'ticket' }
    : analysisPeriod(from.value, through.value)
);
watch(analysis, value => {
  if (value) emit('completed', value);
});
const analyze = () => {
  if (!permitted.value || !period.value || pending.value || analysis.value)
    return;
  const id = canonicalId(props.ticketId);
  if (!id) return;
  props.glpi.run(key.value, (account, signal) =>
    props.glpi.API.analyzeSentiment(account, id, period.value, signal)
  );
};
watch([from, through], () => props.glpi.discard(key.value), { flush: 'sync' });
watch(key, (_value, previous) => {
  props.glpi.discard(previous);
  from.value = '';
  through.value = '';
});
onBeforeUnmount(() => {
  if (!props.readOnly) props.glpi.discard(key.value);
});
const download = () => {
  if (!permitted.value || !analysis.value) return;
  const url = URL.createObjectURL(
    new Blob([analysisReportHtml([analysis.value])], {
      type: 'text/html;charset=utf-8',
    })
  );
  const link = document.createElement('a');
  link.href = url;
  link.download = `glpi-${canonicalId(props.ticketId)}-sentimento.html`;
  link.click();
  URL.revokeObjectURL(url);
};
const time = value => formatGlpiDate(value, analysis.value?.period?.timezone);
</script>

<template>
  <section
    v-if="permitted"
    class="grid gap-3 rounded-2xl border border-n-blue-6 bg-n-solid-2 p-5"
    data-testid="glpi-ticket-sentiment"
  >
    <h3 class="font-semibold">{{ t('JRC_GLPI.sentiment.heading') }}</h3>
    <p
      v-if="!readOnly"
      class="text-sm text-n-slate-11"
    >
      {{
        t(
          wholeTicket
            ? 'JRC_GLPI.sentiment.scope_ticket'
            : 'JRC_GLPI.sentiment.scope'
        )
      }}
    </p>
    <form
      v-if="!readOnly"
      class="flex flex-wrap items-end gap-3"
      @submit.prevent="analyze"
    >
      <label
        v-if="!wholeTicket"
        class="grid gap-1 text-sm"
      >
        {{ t('JRC_GLPI.sentiment.from') }}
        <input
          v-model="from"
          type="date"
          :disabled="pending"
          required
          class="rounded-lg border border-n-weak bg-n-background p-2"
        />
      </label>
      <label
        v-if="!wholeTicket"
        class="grid gap-1 text-sm"
      >
        {{ t('JRC_GLPI.sentiment.through') }}
        <input
          v-model="through"
          type="date"
          :disabled="pending"
          required
          class="rounded-lg border border-n-weak bg-n-background p-2"
        />
      </label>
      <Button
        type="submit"
        :label="
          t(
            pending
              ? 'JRC_GLPI.sentiment.pending'
              : 'JRC_GLPI.sentiment.analyze'
          )
        "
        :disabled="pending || !period || !!analysis"
      />
    </form>
    <p
      v-if="!wholeTicket && from && through && !period"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('JRC_GLPI.sentiment.invalid_period') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('JRC_GLPI.sentiment.failed') }}
      {{ t('JRC_GLPI.source_code', { code: error.code }) }}
    </p>
    <p
      v-if="analysis?.status === 'no_public_text'"
      role="status"
    >
      {{ t('JRC_GLPI.sentiment.no_text') }}
    </p>
    <article
      v-if="report"
      class="grid gap-3"
      data-testid="glpi-sentiment-result"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h4 class="font-semibold">
          {{ t('JRC_GLPI.sentiment.result_title', { id: ticketId }) }}
        </h4>
        <Button
          :label="t('JRC_GLPI.sentiment.download')"
          variant="outline"
          @click="download"
        />
      </div>
      <nav
        class="flex flex-wrap gap-2 border-b border-n-weak pb-3"
        :aria-label="t('JRC_GLPI.sentiment.result_sections')"
      >
        <button
          v-for="item in sections"
          :key="item"
          type="button"
          :aria-pressed="section === item"
          :class="
            section === item
              ? 'bg-n-blue-3 text-n-blue-11 ring-1 ring-inset ring-n-blue-7'
              : 'bg-n-alpha-1 text-n-slate-11'
          "
          class="min-h-10 rounded-lg px-3 py-2 text-sm font-medium focus-visible:outline focus-visible:outline-2"
          @click="section = item"
        >
          {{ t(`JRC_GLPI.sentiment.sections.${item}`) }}
        </button>
      </nav>
      <div
        v-show="section === 'summary'"
        class="grid gap-3"
      >
        <dl class="grid gap-2 text-sm sm:grid-cols-3">
          <div class="grid content-start gap-1 rounded-xl bg-n-blue-2 p-3">
            <dt>{{ t('JRC_GLPI.sentiment.customer') }}</dt>
            <dd class="font-semibold">
              {{ t(`JRC_GLPI.sentiment.labels.${report.customer_sentiment}`) }}
            </dd>
          </div>
          <div
            class="grid content-start gap-1 rounded-xl bg-n-teal-2 p-3 text-n-teal-11"
          >
            <dt>{{ t('JRC_GLPI.sentiment.operator') }}</dt>
            <dd class="font-semibold">
              {{ t(`JRC_GLPI.sentiment.labels.${report.agent_sentiment}`) }}
            </dd>
          </div>
          <div
            class="grid content-start gap-1 rounded-xl bg-n-violet-2 p-3 text-n-violet-11"
          >
            <dt>{{ t('JRC_GLPI.sentiment.score') }}</dt>
            <dd class="font-semibold">{{ score }}</dd>
          </div>
        </dl>
        <p class="whitespace-pre-wrap text-sm">{{ report.summary }}</p>
        <p class="rounded-lg bg-n-amber-2 p-3 text-sm">
          {{ t('JRC_GLPI.sentiment.inferred') }}
        </p>
      </div>
      <div
        v-show="section === 'quality'"
        class="grid gap-3"
      >
        <p class="text-sm">{{ t('JRC_GLPI.sentiment.score_basis') }}</p>
        <dl class="grid gap-2 text-sm sm:grid-cols-2">
          <dt>{{ t('JRC_GLPI.sentiment.score') }}</dt>
          <dd class="font-semibold">{{ score }}</dd>
          <dt>{{ t('JRC_GLPI.sentiment.model') }}</dt>
          <dd>{{ analysis.model }}</dd>
          <dt>{{ t('JRC_GLPI.sentiment.period') }}</dt>
          <dd>
            {{ time(analysis.period.from) }} —
            {{ time(analysis.period.to_exclusive) }} ({{
              analysis.period.timezone
            }})
          </dd>
          <dt>{{ t('JRC_GLPI.sentiment.records') }}</dt>
          <dd>
            {{
              t('JRC_GLPI.sentiment.coverage', {
                analyzed: analysis.source_window.analyzed_records,
                omitted: analysis.source_window.omitted_records,
                truncated: analysis.source_window.truncated_records,
              })
            }}
          </dd>
          <dt>{{ t('JRC_GLPI.sentiment.usage') }}</dt>
          <dd>
            {{
              t('JRC_GLPI.sentiment.tokens', {
                input: analysis.usage.input_tokens,
                output: analysis.usage.output_tokens,
                total: analysis.usage.total_tokens,
              })
            }}
          </dd>
        </dl>
        <p
          v-if="analysis.period.partial"
          class="text-sm text-n-amber-11"
        >
          {{ t('JRC_GLPI.sentiment.partial') }}
        </p>
        <p class="whitespace-pre-wrap text-sm">{{ report.limitations }}</p>
      </div>
      <div
        v-show="section === 'audit'"
        class="grid gap-3 sm:grid-cols-2"
      >
        <div
          v-for="field in ['risks', 'recommendations']"
          :key="field"
          class="grid content-start gap-2 rounded-xl border border-n-weak p-3"
        >
          <h4 class="text-sm font-semibold">
            {{ t(`JRC_GLPI.sentiment.${field}`) }}
          </h4>
          <ul
            v-if="report[field].length"
            class="list-disc space-y-2 pl-5 text-sm"
          >
            <li
              v-for="(value, index) in report[field]"
              :key="index"
            >
              {{ value }}
            </li>
          </ul>
          <p
            v-else
            class="text-sm text-n-slate-11"
          >
            {{ t('JRC_GLPI.sentiment.no_findings') }}
          </p>
        </div>
      </div>
      <div
        v-show="section === 'evidence'"
        class="grid gap-2"
      >
        <p class="text-sm">
          {{ t('JRC_GLPI.sentiment.evidence_source') }}
        </p>
        <ul
          v-if="report.evidence.length"
          class="grid gap-2 text-sm"
        >
          <li
            v-for="(item, index) in report.evidence"
            :key="index"
            class="grid gap-1 rounded-xl border border-n-weak p-3"
          >
            <span class="break-all font-medium text-n-blue-11">
              {{ item.message_id }}
            </span>
            <p class="whitespace-pre-wrap">{{ item.observation }}</p>
          </li>
        </ul>
        <p
          v-else
          class="text-sm text-n-slate-11"
        >
          {{ t('JRC_GLPI.sentiment.no_evidence') }}
        </p>
      </div>
    </article>
  </section>
</template>
