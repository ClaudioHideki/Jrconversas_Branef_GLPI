<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
const props = defineProps({
  glpi: { type: Object, required: true },
  ticketId: { type: [String, Number], default: null },
  items: { type: Array, default: () => [] },
});
const emit = defineEmits(['changed']);
const { t } = useI18n();
const file = ref(null);
const receipt = ref(null);
const key = ref(crypto.randomUUID());
const invalid = ref(false);
const reset = () => {
  file.value = null;
  receipt.value = null;
  invalid.value = false;
  key.value = crypto.randomUUID();
};
const canUpload = computed(() =>
  (props.glpi.state.data.capabilities?.operations || []).some(
    item =>
      item.operation === 'document.upload' &&
      item.supported &&
      item.permitted &&
      item.source_allowed !== false
  )
);
const choose = event => {
  file.value = event.target.files[0] || null;
  invalid.value = !!file.value && file.value.size > 20 * 1024 * 1024;
  receipt.value = null;
  key.value = crypto.randomUUID();
};
const upload = async () => {
  if (
    !file.value ||
    invalid.value ||
    !props.ticketId ||
    receipt.value ||
    !canUpload.value
  )
    return;
  const values = new FormData();
  values.append('file', file.value);
  values.append('name', file.value.name);
  values.append('idempotency_key', key.value);
  const result = await props.glpi.run('document_upload', (account, signal) =>
    props.glpi.API.uploadDocument(account, props.ticketId, values, signal)
  );
  if (result?.command) {
    receipt.value = result.command;
    if (receipt.value.state === 'succeeded') emit('changed');
  } else {
    const error = props.glpi.state.errors.document_upload;
    receipt.value = {
      state: [403, 409, 413, 422].includes(error?.status)
        ? 'rejected'
        : 'indeterminate',
      error_code: error?.code,
    };
  }
};
const check = async () => {
  const result = await props.glpi.read(
    'document_upload',
    receipt.value?.id ? `commands/${receipt.value.id}` : 'commands/lookup',
    receipt.value?.id ? undefined : { idempotency_key: key.value }
  );
  if (result?.command) {
    receipt.value = result.command;
    if (receipt.value.state === 'succeeded') emit('changed');
  }
};
const download = async row => {
  const parent =
    props.ticketId ||
    row.tickets_id ||
    (row.itemtype === 'Ticket' ? row.items_id : null);
  if (!parent || !row.documents_id) return;
  const result = await props.glpi.run(
    'document_download',
    (account, signal) =>
      props.glpi.API.downloadDocument(
        account,
        parent,
        row.documents_id,
        signal
      ),
    { binary: true, maxBytes: 50 * 1024 * 1024 }
  );
  if (!result?.binary) return;
  const url = URL.createObjectURL(result.binary);
  const link = document.createElement('a');
  link.href = url;
  link.download = row.filename || `glpi-document-${row.documents_id}`;
  link.click();
  URL.revokeObjectURL(url);
};
</script>

<template>
  <section
    class="grid gap-3 rounded-xl border border-n-weak p-4"
    data-testid="glpi-documents"
  >
    <h4 class="font-semibold">{{ t('JRC_GLPI.resources.documents') }}</h4>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_GLPI.workspace.documents_help') }}
    </p>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_GLPI.workspace.technical_identity') }}
    </p>
    <div
      v-for="row in items"
      :key="row.id"
      class="flex items-center justify-between gap-2"
    >
      <span class="text-sm">{{
        row.name ||
        row.filename ||
        t('JRC_GLPI.workspace.record_number', { id: row.documents_id })
      }}</span>
      <Button
        type="button"
        size="sm"
        variant="outline"
        :label="t('JRC_GLPI.workspace.download')"
        :disabled="
          glpi.state.loading.document_download ||
          !(
            ticketId ||
            row.tickets_id ||
            (row.itemtype === 'Ticket' && row.items_id)
          )
        "
        @click="download(row)"
      />
    </div>
    <form
      v-if="ticketId && canUpload"
      class="grid gap-2"
      @submit.prevent="upload"
    >
      <label class="grid gap-1 text-xs"
        >{{ t('JRC_GLPI.workspace.upload')
        }}<input
          :key="key"
          type="file"
          :disabled="glpi.state.loading.document_upload || !!receipt"
          @change="choose"
      /></label>
      <p v-if="invalid" role="alert">
        {{ t('JRC_GLPI.workspace.upload_limit') }}
      </p>
      <Button
        type="submit"
        :label="t('JRC_GLPI.workspace.upload')"
        :disabled="
          !file || invalid || glpi.state.loading.document_upload || !!receipt
        "
      />
    </form>
    <p v-else class="text-xs">
      {{
        t(
          ticketId
            ? 'JRC_GLPI.workspace.upload_unavailable'
            : 'JRC_GLPI.workspace.select_parent'
        )
      }}
    </p>
    <div v-if="receipt" role="status" class="grid gap-2 text-sm">
      <p>{{ t(`JRC_GLPI.receipts.${receipt.state}`) }}</p>
      <p v-if="receipt.error_code">
        {{ t('JRC_GLPI.source_code', { code: receipt.error_code }) }}
      </p>
      <Button
        v-if="['pending', 'sending', 'indeterminate'].includes(receipt.state)"
        type="button"
        :label="t('JRC_GLPI.check_send')"
        variant="outline"
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
