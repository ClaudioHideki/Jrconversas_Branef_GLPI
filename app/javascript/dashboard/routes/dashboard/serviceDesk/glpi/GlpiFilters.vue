<script setup>
import { reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
const props = defineProps({
  entities: { type: Array, default: () => [] },
  busy: Boolean,
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
const apply = () =>
  emit(
    'apply',
    Object.fromEntries(
      Object.entries(values).filter(([, value]) => value !== '')
    )
  );
</script>

<template>
  <form
    class="grid gap-3 rounded-xl border border-n-weak p-4 sm:grid-cols-2 xl:grid-cols-4"
    @submit.prevent="apply"
  >
    <label class="grid gap-1 text-xs"
      >{{ t('JRC_GLPI.entity') }}
      <select
        v-model="values.entity_id"
        class="!mb-0 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
      >
        <option value="">{{ t('JRC_SERVICE_DESK.COMMON.all') }}</option>
        <option
          v-for="entity in props.entities"
          :key="entity.id"
          :value="entity.id"
        >
          {{ entity.name }}
        </option>
      </select>
    </label>
    <label class="grid gap-1 text-xs"
      >{{ t('JRC_SERVICE_DESK.COMMON.search')
      }}<input
        v-model="values.search"
        maxlength="200"
        class="!mb-0 w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
    /></label>
    <label
      v-for="field in ['status', 'priority']"
      :key="field"
      class="grid gap-1 text-xs"
      >{{ t(`JRC_GLPI.${field}`) }}
      <select
        v-model="values[field]"
        class="!mb-0 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
      >
        <option value="">{{ t('JRC_SERVICE_DESK.COMMON.all') }}</option>
        <option v-for="value in 6" :key="value" :value="value">
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
      class="grid gap-1 text-xs"
      >{{ t(`JRC_GLPI.${field}`)
      }}<input
        v-model="values[field]"
        type="date"
        class="!mb-0 w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
    /></label>
    <Button
      type="submit"
      class="self-end"
      :label="t('JRC_SERVICE_DESK.COMMON.apply')"
      :disabled="busy"
    />
  </form>
</template>
