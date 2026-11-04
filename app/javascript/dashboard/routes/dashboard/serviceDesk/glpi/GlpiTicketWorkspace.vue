<script setup>
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import GlpiFilters from './GlpiFilters.vue';
import GlpiCoverage from './GlpiCoverage.vue';
import GlpiResourceBoard from './GlpiResourceBoard.vue';
import GlpiOperationForm from './GlpiOperationForm.vue';
import { serviceDeskRouteName } from '../routeDefinitions';
const props = defineProps({
  glpi: { type: Object, required: true },
  screen: { type: String, default: 'tickets' },
  ticketId: { type: [String, Number], default: null },
  fixedFilters: { type: Object, default: () => ({}) },
});
const { t } = useI18n();
const router = useRouter();
const localId = ref(null);
const selectedId = computed(() => props.ticketId || localId.value);
const page = ref(1);
const filters = ref({});
const relation = ref('followups');
const list = computed(() => props.glpi.state.data.tickets);
const detail = computed(() => props.glpi.state.data.detail);
const descriptors = computed(() =>
  (props.glpi.state.data.capabilities?.operations || []).filter(
    item =>
      item.operation.startsWith('ticket.') &&
      (props.screen === 'new'
        ? item.operation === 'ticket.create'
        : item.operation !== 'ticket.create')
  )
);
const relations = [
  'followups',
  'tasks',
  'solutions',
  'validations',
  'actors',
  'actor_groups',
  'actor_suppliers',
  'documents',
  'assets',
  'problem_links',
  'change_links',
  'knowledge_links',
  'history',
  'satisfaction',
];
const load = () => {
  if (props.screen === 'new') return null;
  if (selectedId.value)
    return props.glpi.read('detail', `tickets/${selectedId.value}`);
  return props.glpi.read('tickets', 'tickets', {
    ...filters.value,
    ...props.fixedFilters,
    page: page.value,
    per_page: 25,
  });
};
watch(selectedId, () => {
  props.glpi.discard('detail');
  load();
});
watch(() => props.screen, load, { immediate: true });
const open = id => {
  if (props.glpi.session.state.context?.data_source === 'glpi')
    router.push({
      name: serviceDeskRouteName('detail'),
      params: { accountId: props.glpi.session.accountId.value, ticketId: id },
    });
  else localId.value = id;
};
const create = () =>
  router.push({
    name: serviceDeskRouteName('new'),
    params: { accountId: props.glpi.session.accountId.value },
  });
</script>

<template>
  <section class="grid gap-4" data-testid="glpi-ticket-workspace">
    <GlpiOperationForm
      v-if="screen === 'new'"
      :glpi="glpi"
      :operations="descriptors"
      @succeeded="receipt => receipt.remote_id && open(receipt.remote_id)"
    />
    <template v-else-if="selectedId">
      <p v-if="glpi.state.loading.detail" role="status">
        {{ t('JRC_GLPI.loading') }}
      </p>
      <template v-if="detail">
        <article class="grid gap-3 rounded-xl border border-n-weak p-4">
          <h3 class="text-lg font-semibold">
            {{ t('JRC_GLPI.ticket_number', { id: detail.ticket.id }) }} ·
            {{ detail.ticket.title }}
          </h3>
          <p class="text-sm">
            {{ t(`JRC_GLPI.statuses.${detail.ticket.status}`) }} ·
            {{ t(`JRC_GLPI.priorities.${detail.ticket.priority}`) }}
          </p>
          <div
            v-if="detail.ticket.description_html"
            v-dompurify-html="detail.ticket.description_html"
            class="prose prose-sm max-w-none overflow-x-auto break-words"
          />
          <p v-else class="whitespace-pre-wrap break-words text-sm">
            {{ detail.ticket.description }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{
              t('JRC_GLPI.workspace.source_revision', {
                version: detail.source_version || detail.ticket.date_mod,
              })
            }}
          </p>
          <p class="text-sm">
            {{ t('JRC_GLPI.solution_deadline') }}:
            {{ detail.ticket.time_to_resolve || t('JRC_GLPI.no_deadline') }}
          </p>
        </article>
        <GlpiOperationForm
          :glpi="glpi"
          :operations="descriptors"
          :record="detail.ticket"
          :parent-id="detail.ticket.id"
          :source-version="detail.source_version || ''"
          @succeeded="load"
        />
        <nav
          class="flex flex-wrap gap-2"
          :aria-label="t('JRC_GLPI.workspace.relations')"
        >
          <Button
            v-for="kind in relations"
            :key="kind"
            size="sm"
            :label="t(`JRC_GLPI.resources.${kind}`)"
            :variant="relation === kind ? 'solid' : 'outline'"
            @click="relation = kind"
          />
        </nav>
        <GlpiResourceBoard
          :key="`${detail.ticket.id}:${relation}`"
          :glpi="glpi"
          :resource="relation"
          :parent-id="detail.ticket.id"
        />
      </template>
    </template>
    <template v-else>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h3 class="font-semibold">
          {{
            t(
              screen === 'mine'
                ? 'JRC_GLPI.workspace.my_queue'
                : 'JRC_GLPI.tabs.tickets'
            )
          }}
        </h3>
        <Button
          v-if="glpi.session.state.context?.data_source === 'glpi'"
          :label="t('JRC_GLPI.new_ticket')"
          @click="create"
        />
      </div>
      <GlpiFilters
        :entities="glpi.state.context.entities"
        :busy="glpi.state.loading.tickets"
        @apply="
          filters = $event;
          page = 1;
          load();
        "
      />
      <p v-if="glpi.state.loading.tickets" role="status">
        {{ t('JRC_GLPI.loading') }}
      </p>
      <template v-if="list">
        <GlpiCoverage
          :coverage="list.coverage"
          :observed-at="list.observed_at || list.generated_at || ''"
        />
        <p class="text-sm">
          {{ t('JRC_GLPI.visible_total', { count: list.meta.total }) }}
        </p>
        <div class="overflow-x-auto rounded-xl border border-n-weak">
          <table class="w-full text-left text-sm">
            <thead>
              <tr>
                <th
                  v-for="field in [
                    'id',
                    'title',
                    'entity',
                    'status',
                    'priority',
                    'solution_deadline',
                  ]"
                  :key="field"
                  class="p-3 text-xs"
                >
                  {{ t(`JRC_GLPI.${field}`) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="ticket in list.items"
                :key="ticket.id"
                class="border-t border-n-weak"
              >
                <td class="p-3">{{ ticket.id }}</td>
                <td class="p-3">
                  <button
                    type="button"
                    class="text-left text-n-blue-11 hover:underline"
                    @click="open(ticket.id)"
                  >
                    {{ ticket.title }}
                  </button>
                </td>
                <td class="p-3">
                  {{ ticket.entity || t('JRC_GLPI.unclassified') }}
                </td>
                <td class="p-3">
                  {{ t(`JRC_GLPI.statuses.${ticket.status}`) }}
                </td>
                <td class="p-3">
                  {{ t(`JRC_GLPI.priorities.${ticket.priority}`) }}
                </td>
                <td class="p-3">
                  {{ ticket.solution_deadline || t('JRC_GLPI.no_deadline') }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-if="!list.items.length" class="text-sm">
          {{ t('JRC_GLPI.empty') }}
        </p>
        <Pagination
          v-if="list.meta.total"
          :current-page="list.meta.page"
          :total-items="list.meta.total"
          :items-per-page="list.meta.per_page"
          @update:current-page="
            page = $event;
            load();
          "
        />
      </template>
    </template>
  </section>
</template>
