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
  <details
    class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2 p-3 text-sm"
    data-testid="glpi-sync"
  >
    <summary
      class="flex cursor-pointer flex-wrap items-center gap-2 font-semibold text-n-blue-11 focus-visible:outline focus-visible:outline-2"
    >
      <i
        class="i-lucide-database size-4"
        aria-hidden="true"
      />
      {{ t('JRC_GLPI.visual.collection') }}
      <span
        v-if="receipt"
        class="font-normal text-n-slate-11"
      >
        ·
        {{
          t(
            `JRC_GLPI.sync.${receipt.coverage?.phase === 'queued' ? 'queued' : receipt.state}`
          )
        }}
      </span>
      <i
        class="i-lucide-chevron-down ml-auto size-4"
        aria-hidden="true"
      />
    </summary>
    <div class="mt-3 grid gap-3 border-t border-n-weak pt-3">
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
    </div>
  </details>
</template>
