<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useGlpi } from './useGlpi';
const props = defineProps({
  modelValue: { type: [String, Number], default: '' },
  resource: { type: String, required: true },
  required: Boolean,
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const glpi = useGlpi();
const search = ref('');
const page = ref(1);
const result = computed(() => glpi.state.data.lookup);
const load = () =>
  glpi.read(
    'lookup',
    props.resource === 'ticket_fields'
      ? 'search_fields/tickets'
      : `resources/${props.resource}`,
    props.resource === 'ticket_fields'
      ? undefined
      : { page: page.value, per_page: 25, search: search.value }
  );
watch(
  () => props.resource,
  () => {
    page.value = 1;
    load();
  },
  { immediate: true }
);
</script>

<template>
  <span class="grid gap-2">
    <span class="flex gap-2">
      <input
        v-model="search"
        :aria-label="t('JRC_SERVICE_DESK.COMMON.search')"
        :disabled="disabled"
        maxlength="200"
        class="!mb-0 w-full min-w-0 rounded-lg border border-n-weak px-2 py-2 text-sm"
        @keydown.enter.prevent="
          page = 1;
          load();
        "
      />
      <Button
        type="button"
        size="sm"
        :label="t('JRC_SERVICE_DESK.COMMON.search')"
        variant="outline"
        :disabled="disabled || glpi.state.loading.lookup"
        @click="
          page = 1;
          load();
        "
      />
    </span>
    <select
      :value="modelValue"
      :required="required"
      :disabled="disabled || !!glpi.state.errors.lookup"
      class="!mb-0 w-full rounded-lg border border-n-weak bg-n-solid-1 px-2 py-2 text-sm"
      @change="emit('update:modelValue', $event.target.value)"
    >
      <option value="">{{ t('JRC_SERVICE_DESK.COMMON.select') }}</option>
      <option
        v-for="row in result?.items || result?.fields || []"
        :key="row.id"
        :value="row.id"
      >
        {{
          row.label ||
          row.name ||
          [row.realname, row.firstname].filter(Boolean).join(' ') ||
          row.id
        }}
      </option>
    </select>
    <span
      v-if="glpi.state.errors.lookup"
      role="alert"
      class="text-xs text-n-ruby-11"
      >{{
        t('JRC_GLPI.source_code', { code: glpi.state.errors.lookup.code })
      }}</span
    >
    <span v-if="result?.meta && result.meta.total > 25" class="flex gap-2">
      <Button
        type="button"
        size="xs"
        variant="ghost"
        :label="t('JRC_SERVICE_DESK.COMMON.back')"
        :disabled="page === 1 || glpi.state.loading.lookup"
        @click="
          page -= 1;
          load();
        "
      />
      <span>{{ page }}</span>
      <Button
        type="button"
        size="xs"
        variant="ghost"
        :label="t('JRC_GLPI.workspace.next')"
        :disabled="page * 25 >= result.meta.total || glpi.state.loading.lookup"
        @click="
          page += 1;
          load();
        "
      />
    </span>
  </span>
</template>
