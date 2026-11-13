<script setup>
import { reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { plainText, selectedFilters } from './presentation';
const props = defineProps({
  entities: { type: Array, default: () => [] },
  busy: Boolean,
  initialFilters: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['apply']);
const { t } = useI18n();
const values = reactive({
  entity_id: '',
  search: '',
  status: '',
  priority: '',
  from: '',
  to: '',
});
const applied = ref({});
watch(
  () => props.initialFilters,
  query => {
    Object.keys(values).forEach(key => {
      values[key] = selectedFilters(query)[key] ?? '';
    });
    applied.value = selectedFilters(query);
  },
  { immediate: true, deep: true }
);
const apply = () => {
  applied.value = selectedFilters(values);
  emit('apply', { ...applied.value });
};
const clear = () => {
  Object.keys(values).forEach(key => {
    values[key] = '';
  });
  apply();
};
const remove = key => {
  Object.assign(values, {
    entity_id: '',
    search: '',
    status: '',
    priority: '',
    from: '',
    to: '',
    ...applied.value,
    [key]: '',
  });
  apply();
};
const filterLabel = (key, value) => {
  if (key === 'status') return t(`JRC_GLPI.statuses.${value}`);
  if (key === 'priority') return t(`JRC_GLPI.priorities.${value}`);
  if (key === 'entity_id')
    return plainText(
      props.entities.find(entity => String(entity.id) === String(value))
        ?.name || t('JRC_GLPI.entity_number', { id: value })
    );
  return `${t(`JRC_GLPI.${key === 'search' ? 'workspace.search' : key}`)}: ${value}`;
};
</script>

<template>
  <form
    class="grid min-w-0 gap-4 rounded-2xl border border-n-blue-6 bg-n-solid-2 p-4 shadow-sm sm:grid-cols-2 xl:grid-cols-4"
    @submit.prevent="apply"
  >
    <label class="grid gap-2 text-sm font-medium text-n-slate-12">
      {{ t('JRC_GLPI.entity') }}
      <select
        v-model="values.entity_id"
        class="!mb-0 w-full rounded-lg border border-n-strong bg-n-solid-1 px-3 py-2.5 text-sm focus:border-n-blue-9 focus:ring-2 focus:ring-n-blue-5"
      >
        <option value="">{{ t('JRC_SERVICE_DESK.COMMON.all') }}</option>
        <option
          v-for="entity in props.entities"
          :key="entity.id"
          :value="entity.id"
        >
          {{ plainText(entity.name) }}
        </option>
      </select>
    </label>
    <label class="grid gap-2 text-sm font-medium text-n-slate-12">
      {{ t('JRC_GLPI.workspace.search') }}
      <input
        v-model="values.search"
        maxlength="200"
        class="!mb-0 w-full rounded-lg border border-n-strong bg-n-solid-1 px-3 py-2.5 text-sm focus:border-n-blue-9 focus:ring-2 focus:ring-n-blue-5"
      />
    </label>
    <label
      v-for="field in ['status', 'priority']"
      :key="field"
      class="grid gap-2 text-sm font-medium text-n-slate-12"
    >
      {{ t(`JRC_GLPI.${field}`) }}
      <select
        v-model="values[field]"
        class="!mb-0 w-full rounded-lg border border-n-strong bg-n-solid-1 px-3 py-2.5 text-sm focus:border-n-blue-9 focus:ring-2 focus:ring-n-blue-5"
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
    <label
      v-for="field in ['from', 'to']"
      :key="field"
      class="grid gap-2 text-sm font-medium text-n-slate-12"
    >
      {{ t(`JRC_GLPI.${field}`) }}
      <input
        v-model="values[field]"
        type="date"
        class="!mb-0 w-full rounded-lg border border-n-strong bg-n-solid-1 px-3 py-2.5 text-sm focus:border-n-blue-9 focus:ring-2 focus:ring-n-blue-5"
      />
    </label>
    <Button
      type="submit"
      class="self-end"
      :label="t('JRC_SERVICE_DESK.COMMON.apply')"
      :disabled="busy"
    />
    <button
      type="button"
      class="self-end rounded-lg border border-n-strong bg-n-solid-1 px-3 py-2.5 text-sm focus:border-n-blue-9 focus:ring-2 focus:ring-n-blue-5 font-semibold text-n-slate-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-9"
      data-testid="clear-filters"
      :disabled="busy"
      @click="clear"
    >
      {{ t('JRC_GLPI.visual.clear') }}
    </button>
    <div
      v-if="Object.keys(applied).length"
      class="col-span-full flex flex-wrap items-center gap-2 border-t border-n-weak pt-3"
      :aria-label="t('JRC_GLPI.visual.applied')"
    >
      <span class="text-xs font-semibold text-n-slate-11">
        {{ t('JRC_GLPI.visual.applied') }}
      </span>
      <button
        v-for="(value, key) in applied"
        :key="key"
        type="button"
        :data-filter="key"
        class="rounded-full border border-n-blue-6 bg-n-blue-2 px-3 py-1 text-xs font-semibold text-n-blue-11 focus-visible:outline focus-visible:outline-2"
        :aria-label="
          t('JRC_GLPI.visual.remove', { filter: filterLabel(key, value) })
        "
        :disabled="busy"
        @click="remove(key)"
      >
        {{ filterLabel(key, value) }}
        <i
          class="i-lucide-x size-3"
          aria-hidden="true"
        />
      </button>
    </div>
  </form>
</template>
