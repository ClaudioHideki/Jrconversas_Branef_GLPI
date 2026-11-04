<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import GlpiLookup from './GlpiLookup.vue';
import GlpiRichEditor from './GlpiRichEditor.vue';
import {
  operationBlock,
  operationAttributes,
  fieldResource,
  numericField,
} from '../helpers/glpiScreens';

const props = defineProps({
  glpi: { type: Object, required: true },
  operations: { type: Array, default: () => [] },
  record: { type: Object, default: null },
  parentId: { type: [String, Number], default: null },
  sourceVersion: { type: String, default: '' },
});
const emit = defineEmits(['succeeded']);
const { t, te } = useI18n();
const operation = ref('');
const entityId = ref('');
const values = reactive({});
const initial = reactive({});
const rich = reactive({});
const reason = ref('');
const confirmed = ref(false);
const idempotencyKey = ref(crypto.randomUUID());
const receipt = ref(null);
const descriptor = computed(() =>
  props.operations.find(row => row.operation === operation.value)
);
const blocked = computed(() =>
  descriptor.value ? operationBlock(descriptor.value) : 'unsupported'
);
const busy = computed(() => !!props.glpi.state.loading.operation);
const fields = computed(() => descriptor.value?.fields || []);
const unknownField = computed(() =>
  fields.value.some(field => !te(`JRC_GLPI.fields.${field}`))
);
const missingTarget = computed(
  () => descriptor.value?.verb !== 'post' && !props.record?.id
);
const parent = computed(
  () =>
    props.parentId ||
    (descriptor.value?.parent
      ? props.record?.tickets_id || props.record?.items_id
      : null)
);
const reset = () => {
  receipt.value = null;
  idempotencyKey.value = crypto.randomUUID();
  confirmed.value = false;
  Object.keys(values).forEach(key => delete values[key]);
  fields.value.forEach(field => {
    const aliases = { name: 'title', content: 'description' };
    const html =
      props.record?.[`${field}_html`] ||
      (field === 'content' ? props.record?.description_html : null);
    rich[field] = !!html;
    values[field] =
      html ?? props.record?.[field] ?? props.record?.[aliases[field]] ?? '';
    initial[field] = values[field];
  });
  entityId.value = props.record?.entities_id ?? '';
  reason.value = '';
};
watch(
  () => props.operations,
  operations => {
    if (!operations.some(row => row.operation === operation.value))
      operation.value = operations[0]?.operation || '';
  },
  { immediate: true }
);
watch([operation, () => props.record?.id], reset, { immediate: true });
const multiline = field =>
  [
    'content',
    'answer',
    'comment',
    'comment_submission',
    'comment_validation',
  ].includes(field);
const fieldType = field => {
  if (numericField(field)) return 'number';
  if (['begin', 'end', 'begin_date', 'end_date'].includes(field))
    return 'datetime-local';
  return 'text';
};
const choices = field => {
  if (
    [
      'is_private',
      'is_faq',
      'is_recursive',
      'is_incident',
      'is_request',
      'is_problem',
      'is_change',
    ].includes(field)
  )
    return [0, 1].map(value => ({
      value,
      label: t(
        `JRC_GLPI.choices.${field === 'is_private' ? ['public', 'private'][value] : ['no', 'yes'][value]}`
      ),
    }));
  if (['urgency', 'impact', 'priority'].includes(field))
    return [1, 2, 3, 4, 5, 6].map(value => ({
      value,
      label: t(`JRC_GLPI.priorities.${value}`),
    }));
  if (field === 'status' && operation.value.includes('validation'))
    return [
      { value: 3, label: t('JRC_GLPI.choices.accepted') },
      { value: 4, label: t('JRC_GLPI.choices.refused') },
    ];
  if (field === 'status')
    return [1, 2, 3, 4, 5, 6].map(value => ({
      value,
      label: t(`JRC_GLPI.statuses.${value}`),
    }));
  if (field === 'state')
    return ['information', 'todo', 'done'].map((label, value) => ({
      value,
      label: t(`JRC_GLPI.choices.${label}`),
    }));
  if (field === 'type') {
    const ticket = operation.value.startsWith('ticket.');
    return (
      ticket ? ['incident', 'request'] : ['requester', 'assigned', 'observer']
    ).map((label, index) => ({
      value: index + 1,
      label: t(`JRC_GLPI.${ticket ? label : `choices.${label}`}`),
    }));
  }
  if (field === 'itemtype')
    return [
      'Computer',
      'Monitor',
      'NetworkEquipment',
      'Peripheral',
      'Phone',
      'Printer',
      'Software',
    ].map(value => ({ value, label: t(`JRC_GLPI.choices.${value}`) }));
  return [];
};
const enableRich = field => {
  if (rich[field]) return;
  const element = document.createElement('p');
  element.textContent = values[field];
  values[field] = element.outerHTML;
  rich[field] = true;
};
const check = async () => {
  const response = await props.glpi.read(
    'operation',
    receipt.value?.id ? `commands/${receipt.value.id}` : 'commands/lookup',
    receipt.value?.id ? undefined : { idempotency_key: idempotencyKey.value }
  );
  if (response?.command) {
    receipt.value = response.command;
    if (receipt.value.state === 'succeeded') emit('succeeded', receipt.value);
  }
};
const submit = async () => {
  if (
    !descriptor.value ||
    blocked.value ||
    busy.value ||
    receipt.value ||
    unknownField.value ||
    missingTarget.value
  )
    return;
  if (entityId.value === '' || (descriptor.value.parent && !parent.value))
    return;
  const attributes = operationAttributes(descriptor.value, values);
  if (descriptor.value.verb === 'patch')
    Object.keys(attributes).forEach(field => {
      if (String(attributes[field]) === String(initial[field]))
        delete attributes[field];
    });
  if (
    ['content', 'answer'].some(
      field => attributes[field] !== undefined && rich[field]
    )
  )
    attributes.content_format = 'rich';
  Object.keys(attributes).forEach(field => {
    if (numericField(field)) attributes[field] = Number(attributes[field]);
    else if (fieldType(field) === 'datetime-local')
      attributes[field] = attributes[field].replace('T', ' ');
  });
  if (descriptor.value.parent) attributes.parent_id = parent.value;
  const payload = {
    operation: descriptor.value.operation,
    target_id: descriptor.value.verb === 'post' ? null : props.record.id,
    entity_id: entityId.value,
    attributes,
    idempotency_key: idempotencyKey.value,
    reason: reason.value,
    ...(descriptor.value.verb !== 'post' &&
    (props.sourceVersion || props.record?.date_mod)
      ? { expected_version: props.sourceVersion || props.record.date_mod }
      : {}),
  };
  const response = await props.glpi.run('operation', (account, signal) =>
    props.glpi.API.execute(account, payload, signal)
  );
  if (response?.command) {
    receipt.value = response.command;
    if (receipt.value.state === 'succeeded') emit('succeeded', receipt.value);
  } else {
    const error = props.glpi.state.errors.operation;
    receipt.value = {
      state: [403, 409, 422].includes(error?.status)
        ? 'rejected'
        : 'indeterminate',
      error_code: error?.code,
    };
  }
};
</script>

<template>
  <section
    class="grid gap-3 rounded-xl border border-n-weak p-4"
    data-testid="glpi-operation-form"
  >
    <h3 class="font-semibold">{{ t('JRC_GLPI.workspace.actions') }}</h3>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_GLPI.workspace.technical_identity') }}
    </p>
    <p class="text-xs text-n-amber-11">
      {{ t('JRC_GLPI.workspace.homologation') }}
    </p>
    <p v-if="!operations.length" role="status">
      {{ t('JRC_GLPI.workspace.no_operations') }}
    </p>
    <template v-else>
      <label class="grid gap-1 text-xs"
        >{{ t('JRC_GLPI.workspace.action') }}
        <select
          v-model="operation"
          :disabled="busy || !!receipt"
          class="!mb-0 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
        >
          <option
            v-for="item in operations"
            :key="item.operation"
            :value="item.operation"
          >
            {{
              t(`JRC_GLPI.operations.${item.operation.replaceAll('.', '_')}`)
            }}
          </option>
        </select>
      </label>
      <p v-if="blocked" role="status" class="text-sm text-n-amber-11">
        {{ t(`JRC_GLPI.workspace.blocks.${blocked}`) }}
      </p>
      <p v-else class="text-xs text-n-slate-11">
        {{ t('JRC_GLPI.workspace.item_check') }}
      </p>
      <p v-if="missingTarget" role="status">
        {{ t('JRC_GLPI.workspace.select_record') }}
      </p>
      <p v-if="unknownField" role="alert">
        {{ t('JRC_GLPI.workspace.unsupported_fields') }}
      </p>
      <form
        v-if="descriptor && !blocked && !unknownField"
        class="grid gap-3 sm:grid-cols-2"
        @submit.prevent="submit"
      >
        <label class="grid gap-1 text-xs"
          >{{ t('JRC_GLPI.entity') }}
          <select
            v-model="entityId"
            required
            :disabled="busy || !!receipt"
            class="!mb-0 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          >
            <option value="">{{ t('JRC_SERVICE_DESK.COMMON.select') }}</option>
            <option
              v-for="entity in glpi.state.context?.entities || []"
              :key="entity.id"
              :value="entity.id"
            >
              {{ entity.name }}
            </option>
          </select>
        </label>
        <p v-if="descriptor.parent && !parent" class="text-sm" role="status">
          {{ t('JRC_GLPI.workspace.select_parent') }}
        </p>
        <label
          v-for="field in fields"
          :key="`${operation}:${field}`"
          class="grid gap-1 text-xs"
          :class="multiline(field) ? 'sm:col-span-2' : ''"
        >
          {{ t(`JRC_GLPI.fields.${field}`) }}
          <GlpiLookup
            v-if="fieldResource(field)"
            v-model="values[field]"
            :resource="fieldResource(field)"
            :required="descriptor.required.includes(field)"
            :disabled="busy || !!receipt"
          />
          <select
            v-else-if="field === 'entities_id'"
            v-model="values[field]"
            :required="descriptor.required.includes(field)"
            :disabled="busy || !!receipt"
            class="!mb-0 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          >
            <option value="">{{ t('JRC_SERVICE_DESK.COMMON.select') }}</option>
            <option
              v-for="entity in glpi.state.context?.entities || []"
              :key="entity.id"
              :value="entity.id"
            >
              {{ entity.name }}
            </option>
          </select>
          <select
            v-else-if="choices(field).length"
            v-model="values[field]"
            :required="descriptor.required.includes(field)"
            :disabled="busy || !!receipt"
            class="!mb-0 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          >
            <option value="">{{ t('JRC_SERVICE_DESK.COMMON.select') }}</option>
            <option
              v-for="choice in choices(field)"
              :key="choice.value"
              :value="choice.value"
            >
              {{ choice.label }}
            </option>
          </select>
          <GlpiRichEditor
            v-else-if="['content', 'answer'].includes(field) && rich[field]"
            :key="`${operation}:${record?.id || ''}:${field}`"
            v-model="values[field]"
            :label="t(`JRC_GLPI.fields.${field}`)"
            :disabled="busy || !!receipt"
          />
          <textarea
            v-else-if="multiline(field)"
            v-model="values[field]"
            :required="descriptor.required.includes(field)"
            :disabled="busy || !!receipt"
            rows="4"
            class="!mb-0 w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
          <input
            v-else
            v-model="values[field]"
            :type="fieldType(field)"
            :required="descriptor.required.includes(field)"
            :disabled="busy || !!receipt"
            :min="numericField(field) ? 0 : undefined"
            class="!mb-0 w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
          <Button
            v-if="['content', 'answer'].includes(field) && !rich[field]"
            type="button"
            size="xs"
            variant="ghost"
            :disabled="busy || !!receipt"
            :label="t('JRC_GLPI.workspace.rich_editor')"
            @click="enableRich(field)"
          />
        </label>
        <label class="grid gap-1 text-xs sm:col-span-2"
          >{{ t('JRC_GLPI.workspace.reason')
          }}<input
            v-model="reason"
            :disabled="busy || !!receipt"
            :required="descriptor.verb === 'delete'"
            maxlength="1000"
            class="!mb-0 w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
        /></label>
        <label
          v-if="descriptor.verb === 'delete'"
          class="flex gap-2 text-xs sm:col-span-2"
          ><input
            v-model="confirmed"
            type="checkbox"
            required
            :disabled="busy || !!receipt"
          />{{ t('JRC_GLPI.workspace.confirm_delete') }}</label
        >
        <Button
          type="submit"
          :label="t('JRC_GLPI.workspace.execute')"
          :disabled="
            busy ||
            !!receipt ||
            missingTarget ||
            (descriptor.parent && !parent) ||
            (descriptor.verb === 'delete' && !confirmed)
          "
        />
      </form>
    </template>
    <div
      v-if="receipt"
      class="grid gap-2 rounded-lg bg-n-slate-2 p-3 text-sm"
      role="status"
      data-testid="glpi-command-receipt"
    >
      <p>{{ t(`JRC_GLPI.receipts.${receipt.state}`) }}</p>
      <p v-if="receipt.id">
        {{
          t('JRC_GLPI.workspace.receipt', {
            id: receipt.id,
            technical:
              receipt.technical_user_id ||
              t('JRC_GLPI.workspace.technical_user'),
          })
        }}
      </p>
      <p v-if="receipt.error_code">
        {{ t('JRC_GLPI.source_code', { code: receipt.error_code }) }}
      </p>
      <Button
        v-if="['pending', 'sending', 'indeterminate'].includes(receipt.state)"
        type="button"
        variant="outline"
        :label="t('JRC_GLPI.check_send')"
        :disabled="busy"
        @click="check"
      />
      <Button
        v-if="['succeeded', 'rejected'].includes(receipt.state)"
        type="button"
        variant="outline"
        :label="t('JRC_GLPI.workspace.another_operation')"
        @click="reset"
      />
    </div>
  </section>
</template>
