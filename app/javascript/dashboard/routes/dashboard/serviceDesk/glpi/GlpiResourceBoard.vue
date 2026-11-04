<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import GlpiCoverage from './GlpiCoverage.vue';
import GlpiOperationForm from './GlpiOperationForm.vue';
import GlpiDocuments from './GlpiDocuments.vue';
import { operationFamily } from '../helpers/glpiScreens';

const props = defineProps({
  glpi: { type: Object, required: true },
  resource: { type: String, required: true },
  parentId: { type: [String, Number], default: null },
  parentEntityId: { type: [String, Number], default: null },
  parentVersion: { type: String, default: '' },
  parentKind: { type: String, default: 'tickets' },
});
const { t } = useI18n();
const page = ref(1);
const search = ref('');
const selected = ref(null);
const relation = ref('tasks');
const key = computed(
  () => `resource:${props.parentKind}:${props.parentId || ''}:${props.resource}`
);
const data = computed(() => props.glpi.state.data[key.value]);
const parentType = computed(
  () =>
    ({
      tickets: 'Ticket',
      problems: 'Problem',
      changes: 'Change',
      templates: 'TicketTemplate',
    })[props.parentKind]
);
const parent = computed(
  () =>
    props.parentId ||
    selected.value?.tickets_id ||
    (selected.value?.itemtype === parentType.value
      ? selected.value?.items_id
      : null)
);
const family = computed(() => {
  const base = operationFamily(props.resource);
  if (props.parentKind !== 'tickets') {
    if (props.resource === 'solutions')
      return props.parentKind === 'problems' ? 'problem' : 'change';
    if (
      ['tasks', 'followups', 'validations', 'actors', 'actor_groups'].includes(
        props.resource
      )
    )
      return `${props.parentKind === 'problems' ? 'problem' : 'change'}_${base}`;
  }
  return base;
});
const operations = computed(() =>
  (props.glpi.state.data.capabilities?.operations || []).filter(item => {
    if (!family.value || !item.operation.startsWith(`${family.value}.`))
      return false;
    if (props.resource === 'solutions')
      return item.operation.endsWith('.solve');
    return item.parent ? item.parent === parentType.value : true;
  })
);
const load = () => {
  let path = `resources/${props.resource}`;
  if (props.parentId)
    path =
      props.parentKind === 'tickets'
        ? `tickets/${props.parentId}/relations/${props.resource}`
        : `resources/${props.parentKind}/${props.parentId}/relations/${props.resource}`;
  return props.glpi.read(
    key.value,
    path,
    props.parentId
      ? undefined
      : { page: page.value, per_page: 25, search: search.value }
  );
};
watch(
  () => [props.resource, props.parentId, props.parentKind],
  () => {
    selected.value = null;
    page.value = 1;
    load();
  },
  { immediate: true }
);
const open = async row => {
  selected.value = row;
  if (props.resource === 'templates') relation.value = 'template_mandatory';
  if (!['problems', 'changes', 'knowledge'].includes(props.resource)) return;
  const result = await props.glpi.read(
    `${key.value}:detail`,
    `resources/${props.resource}/${row.id}`
  );
  if (result?.item) selected.value = result.item;
};
const summaryFields = [
  'name',
  'content',
  'answer',
  'comment',
  'comment_submission',
  'comment_validation',
  'status',
  'state',
  'priority',
  'users_id',
  'users_id_tech',
  'groups_id',
  'actiontime',
  'begin',
  'end',
  'date',
  'date_mod',
  'satisfaction',
  'old_value',
  'new_value',
];
</script>

<template>
  <section
    class="grid gap-4"
    :data-testid="`glpi-resource-${resource}`"
  >
    <h3 class="font-semibold">{{ t(`JRC_GLPI.resources.${resource}`) }}</h3>
    <form
      v-if="!parentId"
      class="flex gap-2"
      @submit.prevent="
        page = 1;
        load();
      "
    >
      <input
        v-model="search"
        :aria-label="t('JRC_SERVICE_DESK.COMMON.search')"
        maxlength="200"
        class="!mb-0 min-w-0 flex-1 rounded-lg border border-n-weak px-3 py-2 text-sm"
      />
      <Button
        type="submit"
        :label="t('JRC_SERVICE_DESK.COMMON.search')"
        :disabled="glpi.state.loading[key]"
      />
    </form>
    <p
      v-if="glpi.state.loading[key]"
      role="status"
    >
      {{ t('JRC_GLPI.loading') }}
    </p>
    <p
      v-if="glpi.state.errors[key]"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('JRC_GLPI.source_code', { code: glpi.state.errors[key].code }) }}
    </p>
    <template v-if="data">
      <GlpiCoverage :coverage="data.coverage" />
      <p
        v-if="!data.items.length"
        class="text-sm"
      >
        {{ t('JRC_GLPI.empty_history') }}
      </p>
      <div class="grid gap-2 lg:grid-cols-2">
        <button
          v-for="row in data.items"
          :key="row.id"
          type="button"
          class="grid gap-2 rounded-lg border border-n-weak p-3 text-left hover:bg-n-slate-2"
          :aria-pressed="selected?.id === row.id"
          @click="open(row)"
        >
          <span class="font-semibold">
            {{
              row.name ||
              row.filename ||
              t('JRC_GLPI.workspace.record_number', { id: row.id })
            }}
          </span>
          <span
            v-if="row.is_private !== undefined"
            class="text-xs text-n-slate-11"
          >
            {{
              t(
                row.is_private
                  ? 'JRC_GLPI.workspace.private'
                  : 'JRC_GLPI.workspace.public'
              )
            }}
          </span>
          <span class="line-clamp-3 whitespace-pre-wrap break-words text-sm">
            {{
              row.content ||
              row.answer ||
              row.comment_submission ||
              row.comment_validation ||
              row.comment ||
              ''
            }}
          </span>
          <time class="text-xs text-n-slate-11">
            {{ row.date_mod || row.date || row.begin }}
          </time>
        </button>
      </div>
      <Pagination
        v-if="data.meta?.per_page && data.meta.total"
        :current-page="data.meta.page"
        :items-per-page="data.meta.per_page"
        :total-items="data.meta.total"
        @update:current-page="
          page = $event;
          load();
        "
      />
    </template>
    <article
      v-if="selected"
      class="grid gap-3 rounded-xl border border-n-weak bg-n-slate-2 p-4"
    >
      <h4 class="font-semibold">
        {{ t('JRC_GLPI.workspace.record_number', { id: selected.id }) }}
      </h4>
      <dl class="grid gap-2">
        <template
          v-for="field in summaryFields.filter(
            name => selected[name] !== undefined && selected[name] !== null
          )"
          :key="field"
        >
          <dt class="text-xs font-medium">
            {{ t(`JRC_GLPI.fields.${field}`) }}
          </dt>
          <dd
            v-if="selected[`${field}_html`]"
            v-dompurify-html="selected[`${field}_html`]"
            class="prose prose-sm max-w-none overflow-x-auto break-words"
          />
          <dd
            v-else
            class="whitespace-pre-wrap break-words text-sm"
          >
            {{ selected[field] }}
          </dd>
        </template>
      </dl>
    </article>
    <GlpiDocuments
      v-if="resource === 'documents'"
      :glpi="glpi"
      :ticket-id="parentKind === 'tickets' ? parent : null"
      :items="data?.items || []"
      @changed="load"
    />
    <GlpiOperationForm
      v-if="operations.length"
      :glpi="glpi"
      :operations="operations"
      :record="selected"
      :parent-id="parent"
      :authorized-entity-id="parentEntityId"
      :parent-version="parentVersion"
      :source-version="selected?.date_mod || ''"
      @succeeded="load"
    />
    <section
      v-if="selected && ['problems', 'changes', 'templates'].includes(resource)"
      class="grid gap-3 border-t border-n-weak pt-4"
    >
      <nav
        class="flex flex-wrap gap-2"
        :aria-label="t('JRC_GLPI.workspace.relations')"
      >
        <Button
          v-for="kind in resource === 'templates'
            ? ['template_mandatory', 'template_hidden', 'template_predefined']
            : [
                'tasks',
                'followups',
                'solutions',
                'validations',
                'actors',
                'actor_groups',
                'documents',
                'history',
              ]"
          :key="kind"
          :label="t(`JRC_GLPI.resources.${kind}`)"
          :variant="relation === kind ? 'solid' : 'outline'"
          size="sm"
          @click="relation = kind"
        />
      </nav>
      <GlpiResourceBoard
        :key="`${selected.id}:${relation}`"
        :glpi="glpi"
        :resource="relation"
        :parent-kind="resource"
        :parent-id="selected.id"
        :parent-entity-id="selected.entities_id"
        :parent-version="selected.date_mod || ''"
      />
    </section>
  </section>
</template>
