<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import GlpiLookup from './GlpiLookup.vue';
import GlpiRichEditor from './GlpiRichEditor.vue';
import { commandMatchesBinding } from '../helpers/glpiBinding';
import { useGlpiTicketPolicy } from './useGlpiTicketPolicy';
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
  authorizedEntityId: { type: [String, Number], default: null },
  parentVersion: { type: String, default: '' },
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
const currentReceipt = computed(() =>
  commandMatchesBinding(receipt.value, props.glpi.binding?.() || null)
);
const descriptor = computed(() =>
  props.operations.find(row => row.operation === operation.value)
);
const blocked = computed(() =>
  descriptor.value ? operationBlock(descriptor.value) : 'unsupported'
);
const busy = computed(() => !!props.glpi.state.loading.operation);
const requiresConfirmation = computed(
  () =>
    descriptor.value?.verb === 'delete' || operation.value === 'ticket.restore'
);
watch(
  () => values.itemtype,
  () => {
    if (operation.value === 'asset.create') values.items_id = '';
  }
);
const policyMode = computed(
  () =>
    operation.value === 'ticket.create' &&
    props.glpi.session?.state.context?.data_source === 'glpi'
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
  (descriptor.value?.fields || []).forEach(field => {
    const aliases = { name: 'title', content: 'description' };
    const html =
      props.record?.[`${field}_html`] ||
      (field === 'content' ? props.record?.description_html : null);
    rich[field] = !!html;
    values[field] =
      html ?? props.record?.[field] ?? props.record?.[aliases[field]] ?? '';
    initial[field] = values[field];
  });
  entityId.value = props.record?.entities_id ?? props.authorizedEntityId ?? '';
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
const ticketPolicy = useGlpiTicketPolicy({
  glpi: props.glpi,
  active: policyMode,
  entityId,
  values,
  rich,
});
const {
  form: ticketForm,
  templateId,
  pending: policyPending,
  failed: policyFailed,
  limitations,
  missing: missingPolicyFields,
  placeholder: unchangedPlaceholder,
  available: policyAvailable,
  blocked: policyBlocked,
} = ticketPolicy;
const fields = computed(() =>
  policyMode.value ? ticketPolicy.fields.value : descriptor.value?.fields || []
);
const unknownField = computed(() =>
  fields.value.some(field => !te(`JRC_GLPI.fields.${field}`))
);
const required = field =>
  policyMode.value
    ? ticketPolicy.required.value.includes(field)
    : descriptor.value.required.includes(field);
const fieldDisabled = field =>
  busy.value ||
  !!receipt.value ||
  (policyMode.value &&
    policyPending.value &&
    !['type', 'itilcategories_id'].includes(field));
const lookupFilters = computed(() => {
  if (operation.value === 'asset.create')
    return { ticket_id: parent.value, asset_type: values.itemtype };
  return policyMode.value ? { entity_id: Number(entityId.value) } : {};
});
const lookupResource = field =>
  field === 'items_id' && operation.value === 'asset.create'
    ? 'asset_candidates'
    : fieldResource(field);
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
    return (field === 'priority' ? [1, 2, 3, 4, 5, 6] : [1, 2, 3, 4, 5]).map(
      value => ({
        value,
        label: t(`JRC_GLPI.priorities.${value}`),
      })
    );
  if (field === 'status' && operation.value.includes('validation'))
    return [
      { value: 3, label: t('JRC_GLPI.choices.accepted') },
      { value: 4, label: t('JRC_GLPI.choices.refused') },
    ];
  if (field === 'status' && descriptor.value.itemtype === 'Problem')
    return [1, 7, 2, 3, 4, 5, 8, 6].map(value => ({
      value,
      label: t(`JRC_GLPI.problem_statuses.${value}`),
    }));
  if (field === 'status' && descriptor.value.itemtype === 'Change')
    return [1, 9, 10, 7, 4, 11, 12, 5, 8, 6, 14, 13].map(value => ({
      value,
      label: t(`JRC_GLPI.change_statuses.${value}`),
    }));
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
    if (receipt.value.state === 'succeeded' && currentReceipt.value)
      emit('succeeded', receipt.value);
  }
};
const submit = async () => {
  if (
    !descriptor.value ||
    blocked.value ||
    busy.value ||
    receipt.value ||
    unknownField.value ||
    missingTarget.value ||
    (requiresConfirmation.value && !confirmed.value) ||
    (policyMode.value && policyBlocked.value)
  )
    return;
  if (entityId.value === '' || (descriptor.value.parent && !parent.value))
    return;
  const attributes = operationAttributes(
    policyMode.value
      ? { fields: fields.value.filter(field => field !== 'status') }
      : descriptor.value,
    values
  );
  if (policyMode.value) {
    // Backend repeats ORIGINAL source selection before applying effective values.
    [
      ['type', 'type'],
      ['itilcategories_id', 'category_id'],
    ].forEach(([field, selector]) => {
      if (ticketPolicy.selectors.value[selector] !== undefined)
        attributes[field] = ticketPolicy.selectors.value[selector];
      else delete attributes[field];
    });
  }
  if (policyMode.value && templateId.value)
    attributes.template_id = Number(templateId.value);
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
    else if (fieldType(field) === 'datetime-local') {
      attributes[field] = attributes[field].replace('T', ' ');
      if (attributes[field].length === 16) attributes[field] += ':00';
    }
  });
  if (descriptor.value.parent) attributes.parent_id = parent.value;
  let expectedVersion = props.sourceVersion || props.record?.date_mod;
  if (descriptor.value.verb === 'post')
    expectedVersion = descriptor.value.parent ? props.parentVersion : null;
  const payload = {
    operation: descriptor.value.operation,
    target_id: descriptor.value.verb === 'post' ? null : props.record.id,
    entity_id: entityId.value,
    attributes,
    idempotency_key: idempotencyKey.value,
    ...(reason.value.trim() ? { reason: reason.value.trim() } : {}),
    ...(expectedVersion ? { expected_version: expectedVersion } : {}),
    ...(policyMode.value ? { template_version: ticketForm.value.version } : {}),
  };
  const response = await props.glpi.run('operation', (account, signal) =>
    props.glpi.API.execute(account, payload, signal)
  );
  if (response?.command) {
    receipt.value = response.command;
    if (receipt.value.state === 'succeeded' && currentReceipt.value)
      emit('succeeded', receipt.value);
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
    <p
      v-if="!operations.length"
      role="status"
    >
      {{ t('JRC_GLPI.workspace.no_operations') }}
    </p>
    <template v-else>
      <label class="grid gap-1 text-xs">
        {{ t('JRC_GLPI.workspace.action') }}
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
      <p
        v-if="blocked"
        role="status"
        class="text-sm text-n-amber-11"
      >
        {{ t(`JRC_GLPI.workspace.blocks.${blocked}`) }}
      </p>
      <p
        v-else
        class="text-xs text-n-slate-11"
      >
        {{ t('JRC_GLPI.workspace.item_check') }}
      </p>
      <p
        v-if="missingTarget"
        role="status"
      >
        {{ t('JRC_GLPI.workspace.select_record') }}
      </p>
      <p
        v-if="unknownField"
        role="alert"
      >
        {{ t('JRC_GLPI.workspace.unsupported_fields') }}
      </p>
      <form
        v-if="descriptor && !blocked && !unknownField"
        class="grid gap-3 sm:grid-cols-2"
        @submit.prevent="submit"
      >
        <label class="grid gap-1 text-xs">
          {{ t('JRC_GLPI.entity') }}
          <select
            v-model="entityId"
            required
            :disabled="
              busy ||
              !!receipt ||
              record?.entities_id != null ||
              authorizedEntityId != null
            "
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
        <template v-if="policyMode">
          <label
            v-if="entityId !== ''"
            class="grid gap-1 text-xs"
            data-testid="glpi-template-selector"
          >
            {{ t('JRC_GLPI.ticket_form.template') }}
            <GlpiLookup
              v-model="templateId"
              resource="templates"
              show-selected-reference
              :filters="lookupFilters"
              :placeholder="t('JRC_GLPI.ticket_form.automatic')"
              :disabled="busy || !!receipt"
            />
          </label>
          <p
            v-if="entityId === ''"
            role="status"
            class="text-sm sm:col-span-2"
          >
            {{ t('JRC_GLPI.ticket_form.select_entity') }}
          </p>
          <p
            v-else-if="policyPending"
            role="status"
            class="text-sm sm:col-span-2"
          >
            {{ t('JRC_GLPI.ticket_form.loading') }}
          </p>
          <p
            v-else-if="policyFailed || !policyAvailable"
            role="alert"
            class="text-sm text-n-ruby-11 sm:col-span-2"
          >
            {{ t('JRC_GLPI.ticket_form.unavailable') }}
            <span v-if="glpi.state.errors.ticket_form">
              {{
                t('JRC_GLPI.source_code', {
                  code: glpi.state.errors.ticket_form.code,
                })
              }}
            </span>
            <span v-if="limitations.length">
              {{
                t('JRC_GLPI.ticket_form.unsupported', {
                  fields: limitations.join(', '),
                })
              }}
            </span>
          </p>
          <p
            v-else
            class="text-xs text-n-slate-11 sm:col-span-2"
          >
            {{
              ticketForm.template_id
                ? t('JRC_GLPI.ticket_form.effective', {
                    id: ticketForm.template_id,
                  })
                : t('JRC_GLPI.ticket_form.no_template')
            }}
          </p>
          <p
            v-if="unchangedPlaceholder && !policyPending"
            role="status"
            class="text-sm text-n-amber-11 sm:col-span-2"
          >
            {{ t('JRC_GLPI.ticket_form.replace_placeholder') }}
          </p>
          <p
            v-if="
              missingPolicyFields.length && policyAvailable && !policyPending
            "
            role="status"
            class="text-xs sm:col-span-2"
          >
            {{
              t('JRC_GLPI.ticket_form.required_fields', {
                fields: missingPolicyFields
                  .map(field => t(`JRC_GLPI.fields.${field}`))
                  .join(', '),
              })
            }}
          </p>
        </template>
        <p
          v-if="descriptor.parent && !parent"
          class="text-sm"
          role="status"
        >
          {{ t('JRC_GLPI.workspace.select_parent') }}
        </p>
        <label
          v-for="field in fields"
          :key="`${operation}:${field}`"
          :data-field="field"
          class="grid gap-1 text-xs"
          :class="multiline(field) ? 'sm:col-span-2' : ''"
        >
          {{ t(`JRC_GLPI.fields.${field}`) }}
          <span v-if="policyMode && required(field)">
            {{ t('JRC_GLPI.ticket_form.required') }}
          </span>
          <span
            v-if="policyMode && field === 'status'"
            class="text-sm"
          >
            {{ t(`JRC_GLPI.statuses.${values.status || 1}`) }}
          </span>
          <span
            v-else-if="
              field === 'items_id' &&
              operation === 'asset.create' &&
              (!values.itemtype || !parent)
            "
          >
            {{ t('JRC_GLPI.workspace.select_asset_context') }}
          </span>
          <GlpiLookup
            v-else-if="lookupResource(field)"
            v-model="values[field]"
            :resource="lookupResource(field)"
            :filters="lookupFilters"
            :show-selected-reference="policyMode"
            :required="required(field)"
            :disabled="fieldDisabled(field)"
          />
          <select
            v-else-if="field === 'entities_id'"
            v-model="values[field]"
            :required="required(field)"
            :disabled="fieldDisabled(field)"
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
            :required="required(field)"
            :disabled="fieldDisabled(field)"
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
            :required="required(field)"
            :disabled="fieldDisabled(field)"
          />
          <textarea
            v-else-if="multiline(field)"
            v-model="values[field]"
            :required="required(field)"
            :disabled="fieldDisabled(field)"
            rows="4"
            class="!mb-0 w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
          <input
            v-else
            v-model="values[field]"
            :type="fieldType(field)"
            :required="required(field)"
            :disabled="fieldDisabled(field)"
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
        <label class="grid gap-1 text-xs sm:col-span-2">
          {{ t('JRC_GLPI.workspace.reason') }}
          <input
            v-model="reason"
            :disabled="busy || !!receipt"
            :required="descriptor.verb === 'delete'"
            maxlength="1000"
            class="!mb-0 w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
        </label>
        <label
          v-if="requiresConfirmation"
          class="flex gap-2 text-xs sm:col-span-2"
        >
          <input
            v-model="confirmed"
            type="checkbox"
            required
            :disabled="busy || !!receipt"
          />
          {{
            operation === 'ticket.restore'
              ? t('JRC_GLPI.workspace.confirm_restore')
              : t('JRC_GLPI.workspace.confirm_delete')
          }}
        </label>
        <Button
          type="submit"
          :label="t('JRC_GLPI.workspace.execute')"
          :disabled="
            busy ||
            !!receipt ||
            missingTarget ||
            (policyMode && policyBlocked) ||
            (descriptor.parent && !parent) ||
            (requiresConfirmation && !confirmed)
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
      <p v-if="receipt.connection_id">
        {{
          t('JRC_GLPI.workspace.receipt_origin', {
            id: receipt.connection_id,
            version: receipt.connection_version,
          })
        }}
      </p>
      <p
        v-if="!currentReceipt"
        role="alert"
      >
        {{ t('JRC_GLPI.workspace.receipt_other_source') }}
      </p>
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
