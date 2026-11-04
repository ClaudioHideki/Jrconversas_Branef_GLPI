<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Panel from '../components/ServiceDeskPanel.vue';

const props = defineProps({
  context: { type: Object, required: true },
  busy: Boolean,
});
const emit = defineEmits(['submit', 'check', 'open']);
const { t } = useI18n();
const form = reactive({
  entity_id: '',
  title: '',
  description: '',
  type: 1,
  urgency: 3,
  impact: 3,
  category_id: '',
});
const key = ref(crypto.randomUUID());
const receipt = ref(null);
const attempted = ref(false);
const categories = computed(() =>
  props.context.categories.filter(
    row => String(row.entity_id) === String(form.entity_id)
  )
);
const valid = computed(
  () => form.entity_id !== '' && form.title.trim() && form.description.trim()
);
const submit = () => {
  attempted.value = true;
  emit(
    'submit',
    {
      ...form,
      idempotency_key: key.value,
      requester_id: props.context.requester_id || '',
    },
    value => {
      receipt.value = value;
    }
  );
};
const check = () =>
  emit('check', key.value, value => {
    receipt.value = value;
  });
const reset = () => {
  Object.assign(form, {
    entity_id: '',
    title: '',
    description: '',
    category_id: '',
  });
  receipt.value = null;
  attempted.value = false;
  key.value = crypto.randomUUID();
};
</script>

<template>
  <Panel
    :title="t('JRC_GLPI.new_ticket')"
    icon="i-lucide-ticket-plus"
  >
    <div
      v-if="receipt"
      class="mb-4 grid gap-3 rounded-lg border border-n-weak bg-n-slate-2 p-4"
      role="status"
    >
      <p class="font-semibold">
        {{
          t(`JRC_GLPI.commands.${receipt.state}`, {
            id: receipt.remote_id || receipt.id,
          })
        }}
      </p>
      <p
        v-if="receipt.error_code"
        class="text-sm"
      >
        {{ t('JRC_GLPI.source_code', { code: receipt.error_code }) }}
      </p>
      <p
        v-if="['sending', 'indeterminate', 'pending'].includes(receipt.state)"
        class="text-sm"
      >
        {{ t('JRC_GLPI.ambiguous_help', { id: receipt.id }) }}
      </p>
      <div class="flex gap-2">
        <Button
          v-if="receipt.state === 'succeeded'"
          type="button"
          :label="t('JRC_SERVICE_DESK.COMMON.open')"
          @click="emit('open', receipt.remote_id)"
        />
        <Button
          v-if="['succeeded', 'rejected'].includes(receipt.state)"
          type="button"
          :label="t('JRC_GLPI.another')"
          variant="outline"
          @click="reset"
        />
        <Button
          v-else
          type="button"
          :label="t('JRC_GLPI.check_send')"
          :disabled="busy"
          @click="check"
        />
      </div>
    </div>
    <form
      v-if="!receipt"
      class="grid gap-4"
      @submit.prevent="submit"
    >
      <p class="text-sm text-n-slate-11">
        {{
          t(
            context.requester_id
              ? 'JRC_GLPI.mapped_requester'
              : 'JRC_GLPI.integration_requester'
          )
        }}
      </p>
      <label class="grid gap-1 text-sm">
        {{ t('JRC_GLPI.entity') }}
        <select
          v-model="form.entity_id"
          required
          class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
          :disabled="busy || attempted"
          @change="form.category_id = ''"
        >
          <option
            value=""
            disabled
          >
            {{ t('JRC_SERVICE_DESK.COMMON.select') }}
          </option>
          <option
            v-for="entity in context.entities"
            :key="entity.id"
            :value="entity.id"
          >
            {{ entity.name }}
          </option>
        </select>
      </label>
      <label class="grid gap-1 text-sm">
        {{ t('JRC_GLPI.title') }}
        <input
          v-model="form.title"
          required
          maxlength="255"
          :disabled="busy || attempted"
          class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
        />
      </label>
      <label class="grid gap-1 text-sm">
        {{ t('JRC_GLPI.description') }}
        <textarea
          v-model="form.description"
          required
          maxlength="50000"
          rows="6"
          :disabled="busy || attempted"
          class="!mb-0 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm"
        />
      </label>
      <div class="grid gap-4 sm:grid-cols-3">
        <label class="grid gap-1 text-sm">
          {{ t('JRC_GLPI.type') }}
          <select
            v-model.number="form.type"
            :disabled="busy || attempted"
            class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
          >
            <option :value="1">
              {{ t('JRC_GLPI.incident') }}
            </option>
            <option :value="2">{{ t('JRC_GLPI.request') }}</option>
          </select>
        </label>
        <label
          v-for="field in ['urgency', 'impact']"
          :key="field"
          class="grid gap-1 text-sm"
        >
          {{ t(`JRC_GLPI.${field}`) }}
          <select
            v-model.number="form[field]"
            :disabled="busy || attempted"
            class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
          >
            <option
              v-for="value in 5"
              :key="value"
              :value="value"
            >
              {{ t(`JRC_GLPI.priorities.${value}`) }}
            </option>
          </select>
        </label>
      </div>
      <label class="grid gap-1 text-sm">
        {{ t('JRC_GLPI.category') }}
        <select
          v-model="form.category_id"
          :disabled="busy || attempted"
          class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
        >
          <option value="">
            {{ t('JRC_GLPI.category_default') }}
          </option>
          <option
            v-for="category in categories"
            :key="category.id"
            :value="category.id"
          >
            {{ category.name }}
          </option>
        </select>
      </label>
      <div class="flex flex-wrap gap-2">
        <Button
          v-if="!attempted"
          type="submit"
          :label="t('JRC_GLPI.create_remote')"
          :disabled="busy || !valid"
        />
        <template v-else>
          <Button
            type="button"
            :label="t('JRC_GLPI.check_send')"
            :disabled="busy"
            @click="check"
          />
          <Button
            type="button"
            :label="t('JRC_GLPI.retry_same')"
            variant="outline"
            :disabled="busy"
            @click="submit"
          />
        </template>
      </div>
    </form>
  </Panel>
</template>
