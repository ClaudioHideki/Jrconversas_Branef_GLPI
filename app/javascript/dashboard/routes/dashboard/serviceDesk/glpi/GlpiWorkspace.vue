<script setup>
import { computed, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import TicketForm from './GlpiTicketForm.vue';
import { serviceDeskRouteName } from '../routeDefinitions';
import { useGlpi } from './useGlpi';

const { t } = useI18n();
const router = useRouter();
const glpi = useGlpi();
const { state, session, read } = glpi;
const mode = ref('tickets');
const detailId = ref(null);
const filters = ref({
  entity_id: '',
  status: '',
  priority: '',
  search: '',
  from: '',
  to: '',
});
const page = ref(1);
const context = computed(() => state.context);
const list = computed(() => state.data.tickets);
const detail = computed(() => state.data.detail);
const report = computed(() => state.data.report?.report);
const busy = computed(() => Object.values(state.loading).some(Boolean));
const query = () =>
  Object.fromEntries(
    Object.entries(filters.value).filter(([, value]) => value !== '')
  );
const load = () => {
  if (!context.value?.available) return;
  if (mode.value === 'tickets')
    read('tickets', 'tickets', { ...query(), page: page.value, per_page: 25 });
  if (mode.value === 'reports') read('report', 'reports', query());
};
const init = async () => {
  detailId.value = null;
  const value = await read('context', 'context');
  if (value?.available) load();
};
watch(
  () => session.state.status,
  status => {
    if (status === 'ready') init();
  },
  { immediate: true }
);
watch(mode, () => {
  detailId.value = null;
  load();
});
const open = async id => {
  detailId.value = String(id);
  delete state.data.detail;
  await read('detail', `tickets/${encodeURIComponent(id)}`);
};
const configure = () =>
  router.push({
    name: serviceDeskRouteName('glpi_settings'),
    params: { accountId: session.accountId.value },
  });
const create = async (values, accept) => {
  const result = await glpi.run('create', account =>
    glpi.API.create(account, values)
  );
  if (result?.command) accept(result.command);
  else if ([403, 422].includes(state.error?.status))
    accept({ state: 'rejected', error_code: state.error.code });
};
const check = async (key, accept) => {
  const result = await read('command', 'commands/lookup', {
    idempotency_key: key,
  });
  if (result?.command) accept(result.command);
};
const exportCsv = async () => {
  const account = session.accountId.value;
  const identity = state.context;
  try {
    state.loading.export = true;
    const response = await glpi.API.export(account, query());
    if (session.accountId.value !== account || state.context !== identity)
      return;
    const url = URL.createObjectURL(response.data);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'glpi-tickets.csv';
    link.click();
    URL.revokeObjectURL(url);
  } catch {
    state.error = { code: 'export_unavailable' };
  } finally {
    state.loading.export = false;
  }
};
</script>

<template>
  <section
    class="grid gap-4"
    data-testid="glpi-workspace"
  >
    <header class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="text-xl font-semibold">
          {{ t('JRC_GLPI.heading') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ t('JRC_GLPI.subtitle') }}
        </p>
      </div>
      <div class="flex gap-2">
        <Button
          type="button"
          :label="t('JRC_SERVICE_DESK.COMMON.refresh')"
          variant="outline"
          :disabled="busy"
          @click="init"
        />
        <Button
          v-if="context?.can_manage"
          type="button"
          :label="t('JRC_GLPI.configure')"
          icon="i-lucide-settings"
          variant="outline"
          @click="configure"
        />
      </div>
    </header>
    <div
      v-if="state.error"
      class="rounded-lg border border-n-ruby-6 bg-n-ruby-2 p-4 text-sm"
      role="alert"
    >
      {{ t('JRC_GLPI.error') }}
      {{ t('JRC_GLPI.source_code', { code: state.error.code }) }}
    </div>
    <p
      v-if="state.loading.context"
      class="p-4"
      role="status"
    >
      {{ t('JRC_GLPI.loading') }}
    </p>
    <Panel
      v-else-if="context && !context.available"
      :title="t('JRC_GLPI.not_ready')"
    >
      <p class="text-sm">
        {{
          t(
            context.user_mapping_required
              ? 'JRC_GLPI.mapping_required'
              : 'JRC_GLPI.setup_required'
          )
        }}
      </p>
      <Button
        v-if="context.can_manage"
        type="button"
        class="mt-3"
        :label="t('JRC_GLPI.configure')"
        @click="configure"
      />
    </Panel>
    <template v-if="context?.available">
      <nav
        class="flex flex-wrap gap-2"
        :aria-label="t('JRC_GLPI.heading')"
      >
        <Button
          v-for="tab in [
            'tickets',
            'reports',
            ...(context.can_create ? ['new'] : []),
          ]"
          :key="tab"
          type="button"
          :label="t(`JRC_GLPI.tabs.${tab}`)"
          :variant="mode === tab ? 'solid' : 'outline'"
          :aria-pressed="mode === tab"
          @click="mode = tab"
        />
      </nav>
      <TicketForm
        v-if="mode === 'new' && !detailId"
        :context="context"
        :busy="busy"
        @submit="create"
        @check="check"
        @open="open"
      />
      <Panel
        v-if="detailId"
        :title="t('JRC_GLPI.ticket_number', { id: detailId })"
      >
        <Button
          type="button"
          :label="t('JRC_SERVICE_DESK.COMMON.back')"
          variant="outline"
          @click="detailId = null"
        />
        <template v-if="detail">
          <h3 class="mt-4 font-semibold">{{ detail.ticket.title }}</h3>
          <p class="my-3 text-sm">
            {{ t(`JRC_GLPI.statuses.${detail.ticket.status}`) }} ·
            {{ t(`JRC_GLPI.priorities.${detail.ticket.priority}`) }}
          </p>
          <p class="whitespace-pre-wrap break-words text-sm">
            {{ detail.ticket.description }}
          </p>
          <section
            v-for="(history, kind) in detail.history"
            :key="kind"
            class="mt-5 border-t border-n-weak pt-4"
          >
            <h4 class="mb-2 font-semibold">
              {{ t(`JRC_GLPI.history.${kind}`) }}
            </h4>
            <p
              v-if="!history.available"
              class="text-sm"
            >
              {{ t('JRC_GLPI.history_denied') }}
            </p>
            <p
              v-else-if="!history.items.length"
              class="text-sm text-n-slate-11"
            >
              {{ t('JRC_GLPI.empty_history') }}
            </p>
            <article
              v-for="item in history.items"
              :key="item.id"
              class="mb-3 rounded-lg bg-n-slate-2 p-3"
            >
              <time class="text-xs text-n-slate-11">{{ item.date }}</time>
              <p class="whitespace-pre-wrap break-words text-sm">
                {{ item.content }}
              </p>
            </article>
          </section>
        </template>
      </Panel>
      <template v-if="mode !== 'new' && !detailId">
        <Panel :title="t('JRC_SERVICE_DESK.COMMON.filters')">
          <form
            class="grid gap-3 md:grid-cols-3 xl:grid-cols-4"
            @submit.prevent="
              page = 1;
              load();
            "
          >
            <label class="grid gap-1 text-xs">
              {{ t('JRC_GLPI.entity') }}
              <select
                v-model="filters.entity_id"
                class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
              >
                <option value="">{{ t('JRC_SERVICE_DESK.COMMON.all') }}</option>
                <option
                  v-for="entity in context.entities"
                  :key="entity.id"
                  :value="entity.id"
                >
                  {{ entity.name }}
                </option>
              </select>
            </label>
            <label
              v-for="field in ['status', 'priority']"
              :key="field"
              class="grid gap-1 text-xs"
            >
              {{ t(`JRC_GLPI.${field}`) }}
              <select
                v-model="filters[field]"
                class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
              >
                <option value="">{{ t('JRC_SERVICE_DESK.COMMON.all') }}</option>
                <option
                  v-for="value in 6"
                  :key="value"
                  :value="value"
                >
                  {{
                    t(
                      `JRC_GLPI.${field === 'status' ? 'statuses' : 'priorities'}.${value}`
                    )
                  }}
                </option>
              </select>
            </label>
            <label class="grid gap-1 text-xs">
              {{ t('JRC_SERVICE_DESK.COMMON.search') }}
              <input
                v-model="filters.search"
                maxlength="200"
                class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
              />
            </label>
            <label
              v-for="field in ['from', 'to']"
              :key="field"
              class="grid gap-1 text-xs"
            >
              {{ t(`JRC_GLPI.${field}`) }}
              <input
                v-model="filters[field]"
                type="date"
                class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
              />
            </label>
            <div class="flex items-end gap-2">
              <Button
                type="submit"
                :label="t('JRC_SERVICE_DESK.COMMON.apply')"
                :disabled="busy"
              />
              <Button
                v-if="context.can_export"
                type="button"
                :label="t('JRC_SERVICE_DESK.COMMON.export')"
                variant="outline"
                :disabled="busy"
                @click="exportCsv"
              />
            </div>
          </form>
        </Panel>
        <p
          v-if="busy"
          class="text-sm"
          role="status"
        >
          {{ t('JRC_GLPI.loading') }}
        </p>
        <Panel
          v-if="mode === 'tickets' && list"
          :title="t('JRC_GLPI.visible_total', { count: list.meta.total })"
        >
          <div class="overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead>
                <tr class="border-b border-n-weak">
                  <th
                    v-for="field in [
                      'id',
                      'title',
                      'entity',
                      'status',
                      'priority',
                      'opened_at',
                      'solution_deadline',
                    ]"
                    :key="field"
                    class="p-2 text-xs"
                  >
                    {{ t(`JRC_GLPI.${field}`) }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="ticket in list.items"
                  :key="ticket.id"
                  class="border-b border-n-weak hover:bg-n-slate-2"
                >
                  <td class="p-2">{{ ticket.id }}</td>
                  <td class="min-w-52 p-2">
                    <button
                      class="text-left text-n-blue-11 hover:underline"
                      @click="open(ticket.id)"
                    >
                      {{ ticket.title }}
                    </button>
                  </td>
                  <td class="p-2">
                    {{ ticket.entity || t('JRC_GLPI.unclassified') }}
                  </td>
                  <td class="whitespace-nowrap p-2">
                    {{ t(`JRC_GLPI.statuses.${ticket.status}`) }}
                  </td>
                  <td class="p-2">
                    {{ t(`JRC_GLPI.priorities.${ticket.priority}`) }}
                  </td>
                  <td class="whitespace-nowrap p-2">{{ ticket.opened_at }}</td>
                  <td class="whitespace-nowrap p-2">
                    {{ ticket.solution_deadline || t('JRC_GLPI.no_deadline') }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p
            v-if="!list.items.length"
            class="p-4 text-sm"
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
          <p class="mt-3 text-xs text-n-slate-11">
            {{
              t('JRC_GLPI.generated', {
                time: list.generated_at,
                timezone: context.timezone,
              })
            }}
          </p>
        </Panel>
        <template v-if="mode === 'reports' && report">
          <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <Panel
              v-for="(value, metric) in {
                total: report.total,
                with_deadline: report.solution_sla.with_deadline,
                exceeded: report.solution_sla.exceeded,
                without_deadline: report.solution_sla.without_deadline,
              }"
              :key="metric"
              :title="t(`JRC_GLPI.metrics.${metric}`)"
            >
              <p class="text-3xl font-semibold">{{ value }}</p>
            </Panel>
          </div>
          <div class="grid gap-4 md:grid-cols-2">
            <Panel
              v-for="dimension in [
                'by_status',
                'by_priority',
                'by_entity',
                'by_opening_year',
              ]"
              :key="dimension"
              :title="t(`JRC_GLPI.${dimension}`)"
            >
              <dl class="grid gap-2">
                <div
                  v-for="(count, label) in report[dimension]"
                  :key="label"
                  class="flex justify-between gap-3 border-b border-n-weak pb-2 text-sm"
                >
                  <dt>
                    {{
                      dimension === 'by_status'
                        ? t(`JRC_GLPI.statuses.${label}`)
                        : dimension === 'by_priority'
                          ? t(`JRC_GLPI.priorities.${label}`)
                          : label
                    }}
                  </dt>
                  <dd class="font-semibold">{{ count }}</dd>
                </div>
              </dl>
            </Panel>
          </div>
          <p class="text-xs text-n-slate-11">
            {{ t('JRC_GLPI.report_scope') }}
            {{
              t('JRC_GLPI.generated', {
                time: report.generated_at,
                timezone: context.timezone,
              })
            }}
          </p>
        </template>
      </template>
    </template>
  </section>
</template>
