<script setup>
import { ref, reactive, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskIntake';
import Panel from './ServiceDeskPanel.vue';

const props = defineProps({ accountId: { type: String, required: true }, userId: { type: String, required: true } });
const { t } = useI18n();
const inboxes = ref([]);
const inboxId = ref('');
const loaded = ref(false);
const error = ref(false);
const busy = ref(false);
const readiness = ref(null);
const roster = ref([]);
const form = reactive({ catalogue: null, responses: [], mappings: {}, mode: 'on_handoff', remote_writes_enabled: false });
let revision = 0;
let epoch = 0;
let controller;
const begin = () => {
  epoch += 1;
  controller?.abort();
  controller = new AbortController();
  return { epoch, account: props.accountId, user: props.userId, signal: controller.signal };
};
const accept = (request, response) => {
  if (request.epoch !== epoch || request.signal.aborted) return null;
  if (response.data.account_id !== request.account || response.data.user_id !== request.user) throw new Error('Stale scope');
  return response.data;
};
const reset = () => {
  loaded.value = false;
  error.value = false;
  readiness.value = null;
  roster.value = [];
  revision = 0;
  Object.assign(form, { catalogue: null, responses: [], mappings: {}, mode: 'on_handoff', remote_writes_enabled: false });
};
const load = async () => {
  reset();
  const request = begin();
  try {
    const data = accept(request, await API.get(request.account, inboxId.value, request.signal));
    if (!data) return;
    if (data.record) {
      const { catalogue, responses, mappings, mode, remote_writes_enabled } = data.record;
      Object.assign(form, { catalogue, responses, mappings, mode, remote_writes_enabled });
      revision = data.record.revision;
    }
    loaded.value = true;
  } catch {
    if (request.epoch === epoch) error.value = true;
  }
};
watch(() => [props.accountId, props.userId], async () => {
  reset();
  inboxes.value = [];
  inboxId.value = '';
  const request = begin();
  try {
    const data = accept(request, await API.inboxes(request.account, request.signal));
    if (!data) return;
    inboxes.value = data.inboxes;
    inboxId.value = data.inboxes[0]?.id || '';
    if (inboxId.value) await load();
  } catch {
    if (request.epoch === epoch) error.value = true;
  }
}, { immediate: true });
onBeforeUnmount(() => { epoch += 1; controller?.abort(); });
const draft = () => ({ inbox_id: inboxId.value, catalogue: form.catalogue, responses: form.responses,
  mappings: form.mappings, mode: form.mode, remote_writes_enabled: form.remote_writes_enabled });
const preview = async () => {
  const request = begin();
  busy.value = true;
  error.value = false;
  try {
    readiness.value = accept(request, await API.preview(request.account, draft(), request.signal));
    if (!readiness.value?.ready) form.remote_writes_enabled = false;
  } catch {
    if (request.epoch === epoch) { error.value = true; readiness.value = null; }
  } finally {
    if (request.epoch === epoch) busy.value = false;
  }
};
const publish = async () => {
  const request = begin();
  busy.value = true;
  error.value = false;
  try {
    const data = accept(request, await API.publish(request.account, { ...draft(), expected_revision: revision }, request.signal));
    if (data) { revision = data.record.revision; readiness.value = null; }
  } catch {
    if (request.epoch === epoch) error.value = true;
  } finally {
    if (request.epoch === epoch) busy.value = false;
  }
};
const importFile = async (field, event) => {
  const file = event.target.files?.[0];
  if (!file) return;
  const request = begin();
  try {
    if (file.size > 2 * 1024 * 1024) throw new Error('File too large');
    const value = JSON.parse(await file.text());
    if (request.epoch !== epoch) return;
    if (field === 'roster') {
      if (!Array.isArray(value) || value.length > 200) throw new Error('Invalid roster');
      roster.value = value.map(row => ({ name: String(row.name || ''), email: String(row.email || ''), role: String(row.role || '') }));
    } else {
      form[field] = field === 'responses' ? (value.responses || value) : value;
      readiness.value = null;
      form.remote_writes_enabled = false;
    }
    error.value = false;
  } catch { error.value = true; }
};
</script>

<template>
  <Panel :title="t('JRC_SERVICE_DESK.INTAKE.title')">
    <p class="mb-3 text-sm text-n-slate-11">{{ t('JRC_SERVICE_DESK.INTAKE.help') }}</p>
    <p v-if="error" role="alert" class="mb-3 text-n-ruby-11">{{ t('JRC_SERVICE_DESK.INTAKE.error') }}</p>
    <label class="grid gap-1 text-sm">
      {{ t('JRC_SERVICE_DESK.INTAKE.inbox') }}
      <select v-model="inboxId" :disabled="busy" @change="load">
        <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">{{ inbox.name }}</option>
      </select>
    </label>
    <div v-if="loaded" class="grid gap-3">
      <label v-for="field in ['catalogue', 'responses', 'mappings', 'roster']" :key="field" class="grid gap-1 text-sm">
        {{ t(`JRC_SERVICE_DESK.INTAKE.${field}`) }}
        <input type="file" accept="application/json,.json" :disabled="busy" @change="importFile(field, $event)" />
      </label>
      <p v-if="form.catalogue" class="text-sm">{{ form.catalogue.systems?.map(row => row.label).join(' · ') }}</p>
      <label class="grid gap-1 text-sm">
        {{ t('JRC_SERVICE_DESK.INTAKE.mode') }}
        <select v-model="form.mode" :disabled="busy" @change="readiness = null">
          <option value="on_handoff">{{ t('JRC_SERVICE_DESK.INTAKE.on_handoff') }}</option>
          <option value="on_qualification">{{ t('JRC_SERVICE_DESK.INTAKE.on_qualification') }}</option>
        </select>
      </label>
      <label class="flex items-center gap-2 text-sm">
        <input v-model="form.remote_writes_enabled" data-testid="intake-real-writes" type="checkbox" :disabled="busy || !readiness?.ready" />
        {{ t('JRC_SERVICE_DESK.INTAKE.real_writes') }}
      </label>
      <div v-if="readiness" data-testid="intake-readiness" role="status" class="rounded border border-n-weak p-3 text-sm">
        {{ t(readiness.ready ? 'JRC_SERVICE_DESK.INTAKE.ready' : 'JRC_SERVICE_DESK.INTAKE.blocked') }}
        <ul><li v-for="code in readiness.blockers" :key="code">{{ code }}</li></ul>
      </div>
      <div class="flex flex-wrap gap-2">
        <button data-testid="intake-preview" type="button" class="rounded border border-n-weak px-3 py-2 text-sm" :disabled="busy || !form.catalogue" @click="preview">{{ t('JRC_SERVICE_DESK.INTAKE.preview') }}</button>
        <button data-testid="intake-publish" type="button" class="rounded bg-n-brand px-3 py-2 text-sm text-white" :disabled="busy || !form.catalogue" @click="publish">{{ t('JRC_SERVICE_DESK.INTAKE.publish') }}</button>
      </div>
      <div v-if="roster.length" class="overflow-auto text-sm">
        <p>{{ t('JRC_SERVICE_DESK.INTAKE.roster_help', { count: roster.length }) }}</p>
        <table class="w-full"><tbody><tr v-for="(person, index) in roster" :key="index"><td>{{ person.name }}</td><td>{{ person.email }}</td><td>{{ person.role }}</td></tr></tbody></table>
      </div>
    </div>
  </Panel>
</template>
