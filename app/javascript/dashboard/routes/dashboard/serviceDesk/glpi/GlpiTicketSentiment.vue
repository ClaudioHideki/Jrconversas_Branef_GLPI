<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { canRead, canonicalId } from '../helpers/access';
import { analysisPeriod } from './analysisPeriod';
import { analysisReportHtml } from './ticketAnalysisReport';
import { formatGlpiDate } from './presentation';

const props = defineProps({
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
  const value =
    props.glpi.state.data[key.value]?.analysis || props.savedAnalysis;
  return canonicalId(value?.ticket_id) === canonicalId(props.ticketId)
    ? value
    : null;
});
const report = computed(() => analysis.value?.report);
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
onBeforeUnmount(() => props.glpi.discard(key.value));
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
    <p class="text-sm text-n-slate-11">
      {{
        t(
          wholeTicket
            ? 'JRC_GLPI.sentiment.scope_ticket'
            : 'JRC_GLPI.sentiment.scope'
        )
      }}
    </p>
    <form
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
      <p class="rounded-lg bg-n-amber-2 p-3 text-sm">
        {{ t('JRC_GLPI.sentiment.inferred') }}
      </p>
      <p class="whitespace-pre-wrap text-sm">{{ report.summary }}</p>
      <dl class="grid grid-cols-2 gap-2 text-sm">
        <dt>{{ t('JRC_GLPI.sentiment.customer') }}</dt>
        <dd>
          {{ t(`JRC_GLPI.sentiment.labels.${report.customer_sentiment}`) }}
        </dd>
        <dt>{{ t('JRC_GLPI.sentiment.operator') }}</dt>
        <dd>{{ t(`JRC_GLPI.sentiment.labels.${report.agent_sentiment}`) }}</dd>
        <dt>{{ t('JRC_GLPI.sentiment.score') }}</dt>
        <dd>
          {{ report.quality_score ?? t('JRC_GLPI.sentiment.unavailable') }}
        </dd>
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
      <p class="text-sm">{{ report.limitations }}</p>
      <div
        v-for="field in ['risks', 'recommendations']"
        :key="field"
      >
        <h4 class="text-sm font-semibold">
          {{ t(`JRC_GLPI.sentiment.${field}`) }}
        </h4>
        <ul class="list-disc pl-5 text-sm">
          <li
            v-for="(value, index) in report[field]"
            :key="index"
          >
            {{ value }}
          </li>
        </ul>
      </div>
      <details>
        <summary class="cursor-pointer text-sm font-semibold">
          {{ t('JRC_GLPI.sentiment.evidence') }}
        </summary>
        <ul class="list-disc pl-5 text-sm">
          <li
            v-for="(item, index) in report.evidence"
            :key="index"
          >
            {{ item.message_id }}: {{ item.observation }}
          </li>
        </ul>
      </details>
      <Button
        :label="t('JRC_GLPI.sentiment.download')"
        variant="outline"
        @click="download"
      />
    </article>
  </section>
</template>
