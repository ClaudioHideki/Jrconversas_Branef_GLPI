import {
  computed,
  inject,
  onBeforeUnmount,
  onMounted,
  provide,
  reactive,
  ref,
  watch,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import ServiceDeskAPI from 'dashboard/api/serviceDesk';
import ServiceDeskOperations from 'dashboard/api/serviceDeskOperations';
import {
  createOperationalSession,
  createOperationalState,
} from '../helpers/operationalSession.js';
import { canonicalId, hasServiceDeskFeature } from '../helpers/access.js';
import {
  createServiceDeskSession,
  createSessionState,
} from '../helpers/session.js';
import { serviceDeskRouteName } from '../routeDefinitions';
import { serviceDeskSourceChanged } from '../helpers/glpiBinding';
const KEY = Symbol('jrc-service-desk-session');
export function provideServiceDesk() {
  const route = useRoute();
  const router = useRouter();
  const store = useStore();
  const accountId = computed(() => canonicalId(route.params.accountId));
  const userId = computed(() => canonicalId(store.getters.getCurrentUserID));
  const enabled = computed(() => hasServiceDeskFeature(store, accountId.value));
  const state = reactive(createSessionState());
  const sourceTransitioning = ref(false);
  let sourceIdentity = null;
  let sourceGeneration = 0;
  const session = createServiceDeskSession(ServiceDeskAPI, state);
  const operations = createOperationalSession(
    ServiceDeskOperations,
    session,
    reactive(createOperationalState())
  );
  let refreshGeneration = 0;
  let pendingRefresh;
  watch(
    [accountId, userId, enabled],
    ([account, user, flag]) => {
      sourceIdentity = null;
      sourceGeneration += 1;
      sourceTransitioning.value = false;
      refreshGeneration += 1;
      pendingRefresh = null;
      operations.clear();
      session.start({ accountId: account, userId: user, enabled: flag });
      if (!flag && account && route.name?.startsWith('jrc_service_desk_')) {
        router.replace({ name: 'home', params: { accountId: account } });
      }
    },
    { immediate: true, flush: 'sync' }
  );
  watch(
    [() => state.status, () => state.context],
    () => {
      if (state.status !== 'ready' || !state.context) return;
      const next = state.context;
      const changed = serviceDeskSourceChanged(sourceIdentity, next);
      sourceIdentity = {
        data_source: next.data_source,
        connection_id: next.connection_id,
        connection_version: next.connection_version,
      };
      if (!changed) return;
      sourceGeneration += 1;
      const epoch = sourceGeneration;
      sourceTransitioning.value = true;
      operations.clear();
      router
        .replace({
          name: serviceDeskRouteName('overview'),
          params: { accountId: accountId.value },
        })
        .finally(() => {
          if (epoch === sourceGeneration) sourceTransitioning.value = false;
        });
    },
    { flush: 'sync' }
  );
  watch(
    () => route.name,
    () => {
      refreshGeneration += 1;
      pendingRefresh = null;
    },
    { flush: 'sync' }
  );
  watch(
    () => state.status,
    status => {
      if (status !== 'ready') operations.clear();
    },
    { flush: 'sync' }
  );
  let timer;
  const revalidate = () => {
    if (document.visibilityState === 'hidden') return undefined;
    if (pendingRefresh) return pendingRefresh;
    const generation = refreshGeneration;
    const context = state.context;
    const screen = route.name;
    // Returning to a tab can emit focus and visibilitychange together.
    const task = (async () => {
      await session.revalidate();
      if (
        generation !== refreshGeneration ||
        state.context !== context ||
        route.name !== screen ||
        state.status !== 'ready'
      )
        return;
      const readScreens = [
        'overview',
        'tickets',
        'mine',
        'queues',
        'assignees',
        'sla',
        'reports',
      ];
      if (readScreens.some(name => screen === serviceDeskRouteName(name)))
        operations.state.revision += 1;
    })().finally(() => {
      if (pendingRefresh === task) pendingRefresh = null;
    });
    pendingRefresh = task;
    return task;
  };
  onMounted(() => {
    window.addEventListener('focus', revalidate);
    document.addEventListener('visibilitychange', revalidate);
    timer = window.setInterval(revalidate, 60000);
  });
  onBeforeUnmount(() => {
    refreshGeneration += 1;
    pendingRefresh = null;
    window.clearInterval(timer);
    window.removeEventListener('focus', revalidate);
    document.removeEventListener('visibilitychange', revalidate);
    operations.clear();
    session.dispose();
  });
  const value = {
    ...session,
    state,
    accountId,
    userId,
    enabled,
    operations,
    sourceTransitioning,
  };
  provide(KEY, value);
  return value;
}
export function useServiceDesk() {
  const value = inject(KEY);
  if (!value) throw new Error('Service Desk provider missing');
  return value;
}
