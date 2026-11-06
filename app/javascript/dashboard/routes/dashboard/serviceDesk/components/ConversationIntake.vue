<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskIntake';

const props = defineProps({
  accountId: { type: String, required: true },
  userId: { type: String, required: true },
  conversationId: { type: String, required: true },
});
const { t } = useI18n();
const expanded = ref(false);
const demands = ref([]);
const error = ref(false);
const busy = ref(false);
const confirmed = ref(false);
const sourceVersion = ref('');
const requestKeys = new Map();
let epoch = 0;
let controller;
const clear = () => {
  epoch += 1;
  controller?.abort();
  demands.value = [];
  expanded.value = false;
  error.value = false;
  busy.value = false;
  confirmed.value = false;
  sourceVersion.value = '';
  requestKeys.clear();
};
watch(() => [props.accountId, props.userId, props.conversationId], clear);
onBeforeUnmount(clear);
const run = async action => {
  epoch += 1;
  const current = epoch;
  controller?.abort();
  controller = new AbortController();
  busy.value = true;
  error.value = false;
  try {
    const response = await action(controller.signal);
    if (current !== epoch) return null;
    if (
      response.data.account_id !== props.accountId ||
      response.data.user_id !== props.userId
    )
      throw new Error('Stale scope');
    return response.data;
  } catch {
    if (current === epoch) error.value = true;
    return null;
  } finally {
    if (current === epoch) busy.value = false;
  }
};
const refresh = async () => {
  const result = await run(signal =>
    API.demands(props.accountId, props.conversationId, signal)
  );
  if (result) demands.value = result.demands;
};
const toggle = () => {
  expanded.value = !expanded.value;
  if (expanded.value) refresh();
};
const sendNotice = async row => {
  if (!confirmed.value || !row.remote_id || busy.value) return;
  if (!requestKeys.has(row.id)) requestKeys.set(row.id, crypto.randomUUID());
  const result = await run(signal =>
    API.notice(
      props.accountId,
      row.id,
      {
        kind: 'pending_information',
        request_key: requestKeys.get(row.id),
        human_confirmation: true,
      },
      signal
    )
  );
  if (result) {
    confirmed.value = false;
    await refresh();
  }
};
const complete = async row => {
  if (
    !confirmed.value ||
    !row.remote_id ||
    !sourceVersion.value.trim() ||
    busy.value
  )
    return;
  const result = await run(signal =>
    API.complete(
      props.accountId,
      row.id,
      { source_version: sourceVersion.value.trim() },
      signal
    )
  );
  if (result) {
    confirmed.value = false;
    await refresh();
  }
};
</script>

<template>
  <details
    :open="expanded"
    class="shrink-0 border-b border-n-weak bg-n-solid-1 px-4 py-2 text-sm"
  >
    <summary class="cursor-pointer text-n-slate-11" @click.prevent="toggle">
      {{ t('JRC_SERVICE_DESK.INTAKE.conversation') }}
    </summary>
    <div v-if="expanded" class="max-h-64 overflow-auto py-3">
      <p v-if="error" role="alert" class="text-n-ruby-11">
        {{ t('JRC_SERVICE_DESK.INTAKE.error') }}
      </p>
      <button
        type="button"
        :disabled="busy"
        class="mb-2 rounded border border-n-weak px-2 py-1"
        @click="refresh"
      >
        {{ t('JRC_SERVICE_DESK.INTAKE.refresh') }}
      </button>
      <article
        v-for="row in demands"
        :key="row.id"
        class="mb-3 grid gap-1 rounded border border-n-weak p-3"
      >
        <strong
          >{{ row.selection.system }} ·
          {{ row.selection.subject_label }}</strong
        >
        <span>{{
          t('JRC_SERVICE_DESK.INTAKE.state', { state: row.state })
        }}</span>
        <span>{{
          row.remote_id
            ? t('JRC_SERVICE_DESK.INTAKE.remote', { id: row.remote_id })
            : t('JRC_SERVICE_DESK.INTAKE.no_protocol')
        }}</span>
        <span>{{
          t('JRC_SERVICE_DESK.INTAKE.lifecycle', { state: row.lifecycle_state })
        }}</span>
        <span v-if="row.waiting_deadline">{{
          t('JRC_SERVICE_DESK.INTAKE.deadline', { value: row.waiting_deadline })
        }}</span>
        <span v-if="row.error_code || row.lifecycle_error_code" role="status">{{
          row.error_code || row.lifecycle_error_code
        }}</span>
        <p
          v-for="notice in row.notifications"
          :key="notice.id"
          class="mt-1 text-xs text-n-slate-11"
        >
          {{
            [notice.kind, notice.state, notice.reason_code]
              .filter(Boolean)
              .join(' - ')
          }}
        </p>
        <div
          v-if="
            row.remote_id &&
            (row.permissions.notify || row.permissions.complete)
          "
          class="mt-2 grid gap-2"
        >
          <label class="flex items-center gap-2"
            ><input v-model="confirmed" type="checkbox" />{{
              t('JRC_SERVICE_DESK.INTAKE.confirmation')
            }}</label
          >
          <button
            v-if="row.permissions.notify"
            data-testid="intake-send-notice"
            type="button"
            :disabled="busy || !confirmed"
            class="rounded border border-n-weak px-2 py-1"
            @click="sendNotice(row)"
          >
            {{ t('JRC_SERVICE_DESK.INTAKE.pending_notice') }}
          </button>
          <div v-if="row.permissions.complete" class="grid gap-1">
            <label>{{ t('JRC_SERVICE_DESK.INTAKE.source_version') }}</label>
            <input
              v-model="sourceVersion"
              type="text"
              maxlength="100"
              class="!mb-0 w-full rounded border border-n-weak px-2 py-1"
            />
          </div>
          <button
            v-if="row.permissions.complete"
            type="button"
            :disabled="busy || !confirmed || !sourceVersion.trim()"
            class="rounded border border-n-weak px-2 py-1"
            @click="complete(row)"
          >
            {{ t('JRC_SERVICE_DESK.INTAKE.complete') }}
          </button>
        </div>
      </article>
    </div>
  </details>
</template>
