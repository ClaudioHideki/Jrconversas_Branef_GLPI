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
import GlpiBadge from './GlpiBadge.vue';
import { plainText, formatGlpiDate, selectedFilters } from './presentation';
const props = defineProps({
  glpi: { type: Object, required: true },
  screen: { type: String, default: 'tickets' },
  ticketId: { type: [String, Number], default: null },
  fixedFilters: { type: Object, default: () => ({}) },
  initialFilters: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['filters']);
const { t } = useI18n();
const router = useRouter();
const localId = ref(null);
const trash = ref(false);
const selectedId = computed(() => props.ticketId || localId.value);
const page = ref(1);
const filters = ref(selectedFilters(props.initialFilters));

const entityLabel = ticket =>
  plainText(
    ticket.entity ||
      props.glpi.state.context.entities?.find(
        entity => String(entity.id) === String(ticket.entities_id)
      )?.name ||
      t('JRC_GLPI.entity_number', { id: ticket.entities_id })
  );
const relation = ref('followups');
const list = computed(() => props.glpi.state.data.tickets);
const detail = computed(() => props.glpi.state.data.detail);
const deleted = computed(() =>
  [true, 1, '1'].includes(detail.value?.ticket?.is_deleted)
);
const descriptors = computed(() =>
  (props.glpi.state.data.capabilities?.operations || []).filter(item => {
    if (!item.operation.startsWith('ticket.')) return false;
    if (props.screen === 'new') return item.operation === 'ticket.create';
    if (deleted.value) return item.operation === 'ticket.restore';
    return !['ticket.create', 'ticket.restore'].includes(item.operation);
  })
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
    return props.glpi.read(
      'detail',
      `${trash.value ? 'trash' : 'tickets'}/${selectedId.value}`
    );
  return props.glpi.read('tickets', trash.value ? 'trash' : 'tickets', {
    ...filters.value,
    ...props.fixedFilters,
    page: page.value,
    per_page: 25,
  });
};
const applyFilters = values => {
  filters.value = values;
  page.value = 1;
  emit('filters', values);
  load();
};
watch(
  () => props.initialFilters,
  query => {
    const next = selectedFilters(query);
    if (JSON.stringify(next) === JSON.stringify(filters.value)) return;
    filters.value = next;
    page.value = 1;
    load();
  },
  { deep: true }
);
watch(selectedId, () => {
  props.glpi.discard('detail');
  load();
});
watch(() => props.screen, load, { immediate: true });
const open = id => {
  if (trash.value) {
    localId.value = id;
    return;
  }
  if (props.glpi.session.state.context?.data_source === 'glpi')
    router.push({
      name: serviceDeskRouteName('detail'),
      params: { accountId: props.glpi.session.accountId.value, ticketId: id },
      query: filters.value,
    });
  else localId.value = id;
};
const toggleTrash = () => {
  trash.value = !trash.value;
  localId.value = null;
  page.value = 1;
  filters.value = {};
  emit('filters', {});
  props.glpi.discard('tickets');
  props.glpi.discard('detail');
  load();
};
const succeeded = () => {
  if (trash.value) {
    localId.value = null;
    props.glpi.discard('detail');
  }
  load();
};
const create = () =>
  router.push({
    name: serviceDeskRouteName('new'),
    params: { accountId: props.glpi.session.accountId.value },
  });
</script>

<template>
  <section
    class="grid gap-4"
    data-testid="glpi-ticket-workspace"
  >
    <GlpiOperationForm
      v-if="screen === 'new'"
      :glpi="glpi"
      :operations="descriptors"
      @succeeded="receipt => receipt.remote_id && open(receipt.remote_id)"
    />
    <template v-else-if="selectedId">
      <p
        v-if="glpi.state.loading.detail"
        role="status"
      >
        {{ t('JRC_GLPI.loading') }}
      </p>
      <template v-if="detail">
        <Button
          v-if="trash"
          :label="t('JRC_GLPI.workspace.trash_back')"
          @click="localId = null"
        />
        <article
          class="grid min-w-0 gap-4 rounded-2xl border border-n-blue-6 bg-n-solid-2 p-5 shadow-sm"
        >
          <p
            v-if="deleted"
            data-testid="glpi-deleted-state"
            class="text-sm text-n-ruby-11"
          >
            {{ t('JRC_GLPI.workspace.deleted') }}
          </p>
          <h3 class="text-lg font-semibold">
            {{
              t('JRC_GLPI.workspace.record_title', {
                number: t('JRC_GLPI.ticket_number', { id: detail.ticket.id }),
                title: detail.ticket.title,
              })
            }}
          </h3>
          <p class="text-sm">
            {{
              t('JRC_GLPI.workspace.record_state', {
                status: t(`JRC_GLPI.statuses.${detail.ticket.status}`),
                priority: t(`JRC_GLPI.priorities.${detail.ticket.priority}`),
              })
            }}
          </p>
          <div
            v-if="detail.ticket.description_html"
            v-dompurify-html="detail.ticket.description_html"
            class="prose prose-sm max-w-none overflow-x-auto break-words"
          />
          <p
            v-else
            class="whitespace-pre-wrap break-words text-sm"
          >
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
            {{
              t('JRC_GLPI.workspace.deadline_value', {
                value: detail.ticket.time_to_resolve
                  ? formatGlpiDate(
                      detail.ticket.time_to_resolve,
                      glpi.state.context.timezone
                    )
                  : t('JRC_GLPI.no_deadline'),
              })
            }}
          </p>
        </article>
        <GlpiOperationForm
          :glpi="glpi"
          :operations="descriptors"
          :record="detail.ticket"
          :parent-id="detail.ticket.id"
          :authorized-entity-id="detail.ticket.entities_id"
          :parent-version="detail.source_version || ''"
          :source-version="detail.source_version || ''"
          @succeeded="succeeded"
        />
        <nav
          v-if="!deleted"
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
          v-if="!deleted"
          :key="`${detail.ticket.id}:${relation}`"
          :glpi="glpi"
          :resource="relation"
          :parent-id="detail.ticket.id"
          :parent-entity-id="detail.ticket.entities_id"
          :parent-version="detail.source_version || ''"
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
          v-if="glpi.state.context?.can_manage_trash"
          data-testid="glpi-trash-toggle"
          :label="
            trash
              ? t('JRC_GLPI.workspace.active_tickets')
              : t('JRC_GLPI.workspace.trash')
          "
          @click="toggleTrash"
        />
        <p
          v-if="trash"
          class="text-sm"
        >
          {{ t('JRC_GLPI.workspace.trash') }}
        </p>
        <Button
          v-if="!trash && glpi.session.state.context?.data_source === 'glpi'"
          :label="t('JRC_GLPI.new_ticket')"
          @click="create"
        />
      </div>
      <GlpiFilters
        :entities="glpi.state.context.entities"
        :busy="glpi.state.loading.tickets"
        :initial-filters="filters"
        @apply="applyFilters"
      />
      <p
        v-if="glpi.state.loading.tickets"
        role="status"
      >
        {{ t('JRC_GLPI.loading') }}
      </p>
      <template v-if="list">
        <GlpiCoverage
          :coverage="list.coverage"
          :observed-at="list.observed_at || list.generated_at || ''"
        />
        <p class="text-sm font-semibold text-n-slate-12">
          {{
            list.meta.total == null
              ? t('JRC_GLPI.visual.unavailable_total')
              : t('JRC_GLPI.visible_total', { count: list.meta.total })
          }}
        </p>
        <div
          class="min-w-0 overflow-x-auto rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
        >
          <table class="w-full text-left text-sm">
            <thead class="bg-n-slate-2 text-n-slate-12">
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
                  class="whitespace-nowrap px-4 py-3 text-sm font-semibold"
                >
                  {{ t(`JRC_GLPI.${field}`) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="ticket in list.items"
                :key="ticket.id"
                class="border-t border-n-weak transition-colors hover:bg-n-blue-2"
              >
                <td class="p-4 font-semibold text-n-blue-11">
                  #{{ ticket.id }}
                </td>
                <td class="p-3">
                  <button
                    type="button"
                    class="min-w-48 text-left font-semibold text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2"
                    @click="open(ticket.id)"
                  >
                    {{ plainText(ticket.title) }}
                  </button>
                </td>
                <td class="p-3">
                  {{ entityLabel(ticket) }}
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
                  <span class="whitespace-nowrap">
                    {{
                      ticket.solution_deadline
                        ? formatGlpiDate(
                            ticket.solution_deadline,
                            glpi.state.context.timezone
                          )
                        : t('JRC_GLPI.no_deadline')
                    }}
                  </span>
                  <span
                    v-if="[true, 1, '1'].includes(ticket.solution_exceeded)"
                    class="mt-1 block text-xs font-semibold text-n-ruby-11"
                  >
                    {{ t('JRC_GLPI.visual.exceeded') }}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p
          v-if="!list.items.length && list.meta.total != null"
          class="text-sm"
        >
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
