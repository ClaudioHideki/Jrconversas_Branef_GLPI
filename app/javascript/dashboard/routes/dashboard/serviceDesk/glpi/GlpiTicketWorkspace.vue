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
const trash = ref(false);
const selectedId = computed(() => props.ticketId || localId.value);
const page = ref(1);
const filters = ref({});
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
    });
  else localId.value = id;
};
const toggleTrash = () => {
  trash.value = !trash.value;
  localId.value = null;
  page.value = 1;
  filters.value = {};
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
    <p
      v-if="glpi.state.errors[selectedId ? 'detail' : 'tickets']"
      role="alert"
    >
      {{
        t('JRC_GLPI.source_code', {
          code: glpi.state.errors[selectedId ? 'detail' : 'tickets'].code,
        })
      }}
    </p>
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
        <article class="grid gap-3 rounded-xl border border-n-weak p-4">
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
                value:
                  detail.ticket.time_to_resolve || t('JRC_GLPI.no_deadline'),
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
        @apply="
          filters = $event;
          page = 1;
          load();
        "
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
        <p
          v-if="!list.items.length"
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
