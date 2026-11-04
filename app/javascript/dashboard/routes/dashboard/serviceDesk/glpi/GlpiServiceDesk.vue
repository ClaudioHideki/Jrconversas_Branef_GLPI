<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import { useGlpi } from './useGlpi';
import { glpiScreen } from '../helpers/glpiScreens';
import GlpiTicketWorkspace from './GlpiTicketWorkspace.vue';
import GlpiOverview from './GlpiOverview.vue';
import GlpiResourceBoard from './GlpiResourceBoard.vue';
import GlpiSync from './GlpiSync.vue';
import { serviceDeskRouteName } from '../routeDefinitions';

const props = defineProps({
  screen: { type: String, default: 'tickets' },
  ticketId: { type: [String, Number], default: null },
});
const { t } = useI18n();
const router = useRouter();
const glpi = useGlpi();
const { session, state, read } = glpi;
const screenDefinition = computed(() => glpiScreen(props.screen));
const initialized = ref(false);
let generation = 0;
onBeforeUnmount(() => {
  generation += 1;
});
const initialize = async () => {
  generation += 1;
  const epoch = generation;
  initialized.value = false;
  const context = await read('context', 'context');
  if (epoch !== generation) return;
  if (!context && state.errors.context?.code === 'configuration_changed') {
    await session.revalidate();
    if (epoch !== generation) return;
    await router.replace({
      name: serviceDeskRouteName('overview'),
      params: { accountId: session.accountId.value },
    });
    return;
  }
  if (context?.available) await read('capabilities', 'capabilities');
  if (epoch === generation) initialized.value = !!context?.available;
};
watch(
  [session.accountId, session.userId, () => session.state.status],
  () => {
    if (session.state.status === 'ready') initialize();
  },
  { immediate: true }
);
</script>

<template>
  <section
    class="grid gap-4"
    data-testid="glpi-service-desk"
  >
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="text-xl font-semibold">{{ t('JRC_GLPI.heading') }}</h2>
        <p class="text-sm text-n-slate-11">
          {{ t('JRC_GLPI.workspace.source') }}
        </p>
      </div>
      <Button
        :label="t('JRC_SERVICE_DESK.COMMON.refresh')"
        variant="outline"
        :disabled="state.loading.context"
        @click="initialize"
      />
    </header>
    <div
      v-for="(error, key) in state.errors"
      :key="key"
      role="alert"
      class="rounded-lg border border-n-ruby-6 bg-n-ruby-2 p-3 text-sm"
    >
      {{ t('JRC_GLPI.error') }}
      {{ t('JRC_GLPI.source_code', { code: error.code }) }}
    </div>
    <p
      v-if="state.loading.context"
      role="status"
    >
      {{ t('JRC_GLPI.loading') }}
    </p>
    <p
      v-else-if="state.context && !state.context.available"
      role="alert"
      class="rounded-lg border border-n-amber-6 p-4"
    >
      {{ t('JRC_GLPI.workspace.unavailable') }}
    </p>
    <template v-else-if="state.context?.available && initialized">
      <GlpiSync
        v-if="state.context.can_manage"
        :glpi="glpi"
        @updated="initialize"
      />
      <GlpiOverview
        v-if="screenDefinition?.kind === 'overview'"
        :key="screen"
        :glpi="glpi"
        :screen="screen"
      />
      <GlpiTicketWorkspace
        v-else-if="['tickets', 'ticket'].includes(screenDefinition?.kind)"
        :key="`${screen}:${ticketId || ''}`"
        :glpi="glpi"
        :screen="screen"
        :ticket-id="ticketId"
        :fixed-filters="screenDefinition.filters || {}"
      />
      <GlpiResourceBoard
        v-else-if="screenDefinition?.kind === 'resource'"
        :key="screen"
        :glpi="glpi"
        :resource="screenDefinition.resource"
      />
      <p
        v-else
        role="status"
        class="rounded-lg border border-n-weak p-4"
      >
        {{ t('JRC_GLPI.workspace.not_applicable') }}
      </p>
    </template>
  </section>
</template>
