<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import GlpiFilters from './GlpiFilters.vue';
import GlpiCoverage from './GlpiCoverage.vue';
import GlpiBadge from './GlpiBadge.vue';
import GlpiTicketSentiment from './GlpiTicketSentiment.vue';
import { analysisPeriod } from './analysisPeriod';
import { plainText, selectedFilters } from './presentation';

const props = defineProps({
  glpi: { type: Object, required: true },
  initialFilters: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['filters']);
const { t } = useI18n();
const filters = ref(selectedFilters(props.initialFilters));
const page = ref(1);
const selected = ref(null);
const list = computed(() => props.glpi.state.data.analysisTickets);
const pending = computed(() => props.glpi.state.loading.analysisTickets);
const period = computed(() =>
  analysisPeriod(filters.value.from, filters.value.to)
);
const invalid = computed(
  () => !!(filters.value.from || filters.value.to) && !period.value
);
const load = () => {
  selected.value = null;
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
  }
);
load();
onBeforeUnmount(() => props.glpi.discard('analysisTickets'));
</script>

<template>
  <section
    class="grid min-w-0 gap-4"
    data-testid="glpi-ticket-analysis"
  >
    <p class="text-sm text-n-slate-11">{{ t('JRC_GLPI.analysis.scope') }}</p>
    <GlpiFilters
      :entities="glpi.state.context.entities"
      :busy="pending"
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
                  @click="selected = ticket"
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
      v-if="selected"
      class="grid gap-3"
      data-testid="selected-analysis-ticket"
    >
      <h3 class="font-semibold">
        #{{ selected.id }} · {{ plainText(selected.title) }}
      </h3>
      <GlpiTicketSentiment
        :key="`${selected.id}:${filters.from || ''}:${filters.to || ''}`"
        :glpi="glpi"
        :ticket-id="selected.id"
        :initial-from="filters.from || ''"
        :initial-through="filters.to || ''"
      />
    </section>
  </section>
</template>
