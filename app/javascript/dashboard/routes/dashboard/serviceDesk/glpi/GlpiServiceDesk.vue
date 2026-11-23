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
import { groupErrors, selectedFilters } from './presentation';

const props = defineProps({
  screen: { type: String, default: 'tickets' },
  ticketId: { type: [String, Number], default: null },
});
const { t } = useI18n();
const router = useRouter();
const initialFilters = computed(() =>
  selectedFilters(router?.currentRoute?.value?.query)
);
const persistFilters = query => router.replace({ query });
const glpi = useGlpi();
const { session, state, read } = glpi;
const screenDefinition = computed(() => glpiScreen(props.screen));
const errors = computed(() => groupErrors(state.errors));
const screenTitle = computed(() =>
  ['glpi', 'detail', 'edit', 'new'].includes(props.screen)
    ? t(`JRC_GLPI.visual.titles.${props.screen}`)
    : t(`JRC_SERVICE_DESK.SCREENS.${props.screen}`)
);
const catalogResource = ref('templates');
watch(
  () => props.screen,
  () => {
    catalogResource.value = 'templates';
  }
);
const resource = computed(() =>
  props.screen === 'catalog'
    ? catalogResource.value
    : screenDefinition.value?.resource
);
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
    class="grid min-w-0 grid-cols-1 gap-5"
    data-testid="glpi-service-desk"
  >
    <header
      class="flex flex-wrap items-start justify-between gap-4 rounded-2xl border border-n-blue-6 bg-gradient-to-r from-n-blue-2 to-n-solid-2 p-5 shadow-sm"
    >
      <div>
        <p
          class="mb-2 flex items-center gap-2 text-xs font-bold uppercase tracking-wide text-n-blue-11"
        >
          <i
            class="i-lucide-headset size-4"
            aria-hidden="true"
          />
          {{ t('JRC_GLPI.visual.service_desk') }}
        </p>
        <h2 class="text-2xl font-bold text-n-slate-12">{{ screenTitle }}</h2>
        <p class="mt-1 text-sm text-n-slate-11">
          {{
            t(`JRC_GLPI.visual.help.${screenDefinition?.kind || 'resource'}`)
          }}
        </p>
        <p class="text-sm text-n-slate-11">
          {{ t('JRC_GLPI.workspace.source') }}
          <span
            v-if="state.context?.available"
            class="mt-2 block text-xs font-semibold text-n-blue-11"
          >
            {{
              t('JRC_GLPI.visual.timezone', {
                timezone:
                  state.context.timezone ||
                  t('JRC_GLPI.visual.unknown_timezone'),
              })
            }}
          </span>
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
      v-for="error in errors"
      :key="error.code"
      role="alert"
      class="rounded-lg border border-n-ruby-6 bg-n-ruby-2 p-3 text-sm"
    >
      <p class="font-semibold">
        {{
          t(
            error.code === 'ERROR_RIGHT_MISSING'
              ? 'JRC_GLPI.visual.right_missing'
              : error.code === 'forbidden'
                ? 'JRC_GLPI.visual.forbidden'
                : 'JRC_GLPI.error'
          )
        }}
      </p>
      <details class="mt-2 text-xs">
        <summary class="cursor-pointer font-semibold">
          {{
            t('JRC_GLPI.visual.error_details', {
              count: error.operations.length,
            })
          }}
        </summary>
        <p class="mt-2">
          {{ t('JRC_GLPI.source_code', { code: error.code }) }}
        </p>
        <ul class="mt-1 list-inside list-disc">
          <li
            v-for="operation in error.operations"
            :key="operation"
          >
            {{ operation }}
          </li>
        </ul>
      </details>
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
      <nav
        v-if="screen === 'catalog'"
        class="flex flex-wrap gap-2"
        :aria-label="t('JRC_GLPI.workspace.catalog')"
      >
        <Button
          :label="t('JRC_GLPI.resources.templates')"
          :variant="catalogResource === 'templates' ? 'solid' : 'outline'"
          :aria-pressed="catalogResource === 'templates'"
          @click="catalogResource = 'templates'"
        />
        <Button
          :label="t('JRC_GLPI.resources.categories')"
          :variant="catalogResource === 'categories' ? 'solid' : 'outline'"
          :aria-pressed="catalogResource === 'categories'"
          @click="catalogResource = 'categories'"
        />
      </nav>
      <GlpiOverview
        v-if="screenDefinition?.kind === 'overview'"
        :key="screen"
        :glpi="glpi"
        :screen="screen"
        :initial-filters="initialFilters"
        @filters="persistFilters"
      />
      <GlpiTicketWorkspace
        v-else-if="['tickets', 'ticket'].includes(screenDefinition?.kind)"
        :key="`${screen}:${ticketId || ''}`"
        :glpi="glpi"
        :screen="screen"
        :ticket-id="ticketId"
        :fixed-filters="screenDefinition.filters || {}"
        :initial-filters="initialFilters"
        @filters="persistFilters"
      />
      <GlpiResourceBoard
        v-else-if="screenDefinition?.kind === 'resource'"
        :key="`${screen}:${resource}`"
        :glpi="glpi"
        :resource="resource"
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
