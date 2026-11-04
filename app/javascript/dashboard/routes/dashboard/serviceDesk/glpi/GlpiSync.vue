<script setup>
import { computed, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import GlpiCoverage from './GlpiCoverage.vue';
const props = defineProps({ glpi: { type: Object, required: true } });
const emit = defineEmits(['updated']);
const { t } = useI18n();
const receipt = computed(() => props.glpi.state.data.sync?.sync);
const coverage = computed(() => ({
  ...receipt.value?.coverage,
  state: ['complete', 'partial'].includes(receipt.value?.state)
    ? receipt.value.state
    : 'unavailable',
}));
let timer;
let disposed = false;
onBeforeUnmount(() => {
  disposed = true;
  clearTimeout(timer);
});
const poll = async id => {
  if (disposed) return;
  const result = await props.glpi.read('sync', `sync/${id}`);
  if (disposed || !result?.sync) return;
  if (result.sync.state === 'running') timer = setTimeout(() => poll(id), 2000);
  else emit('updated');
};
const start = async () => {
  clearTimeout(timer);
  const result = await props.glpi.run('sync', (account, signal) =>
    props.glpi.API.startSync(account, signal)
  );
  if (result?.sync && !disposed)
    timer = setTimeout(() => poll(result.sync.id), 2000);
};
const cancel = async () => {
  clearTimeout(timer);
  const result = await props.glpi.run('sync', (account, signal) =>
    props.glpi.API.cancelSync(account, receipt.value.id, signal)
  );
  if (result?.sync?.state === 'running' && !disposed)
    timer = setTimeout(() => poll(result.sync.id), 2000);
};
props.glpi.read('sync', 'sync').then(result => {
  if (result?.sync?.state === 'running' && !disposed)
    timer = setTimeout(() => poll(result.sync.id), 2000);
});
</script>

<template>
  <section
    class="grid gap-2 rounded-xl border border-n-weak p-4"
    data-testid="glpi-sync"
  >
    <h3 class="font-semibold">{{ t('JRC_GLPI.workspace.sync_heading') }}</h3>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_GLPI.workspace.sync_help') }}
    </p>
    <Button
      type="button"
      :label="t('JRC_GLPI.workspace.sync_start')"
      :disabled="glpi.state.loading.sync || receipt?.state === 'running'"
      @click="start"
    />
    <template v-if="receipt">
      <p role="status">
        {{
          t(
            `JRC_GLPI.sync.${receipt.coverage?.phase === 'queued' ? 'queued' : receipt.state}`
          )
        }}
      </p>
      <GlpiCoverage
        :coverage="coverage"
        :observed-at="receipt.finished_at || receipt.started_at || ''"
      />
      <Button
        v-if="receipt.state === 'running'"
        type="button"
        :label="t('JRC_SERVICE_DESK.COMMON.cancel')"
        variant="outline"
        :disabled="glpi.state.loading.sync"
        @click="cancel"
      />
    </template>
  </section>
</template>
