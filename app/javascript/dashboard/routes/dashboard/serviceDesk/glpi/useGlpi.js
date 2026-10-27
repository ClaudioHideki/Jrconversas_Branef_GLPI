import { onBeforeUnmount, reactive, watch } from 'vue';
import API from 'dashboard/api/serviceDeskGlpi';
import { useServiceDesk } from '../composables/useServiceDesk';

export function useGlpi() {
  const session = useServiceDesk();
  const state = reactive({ context: null, error: null, loading: {}, data: {} });
  let generation = 0;
  const requests = new Map();
  const clear = () => {
    generation += 1;
    requests.forEach(controller => controller.abort());
    requests.clear();
    state.context = null;
    state.data = {};
    state.loading = {};
    state.error = null;
  };
  watch(
    [session.accountId, session.userId, () => session.state.status],
    clear,
    { flush: 'sync' }
  );
  onBeforeUnmount(clear);
  const run = async (key, action) => {
    const epoch = generation;
    const accountId = session.accountId.value;
    const userId = session.userId.value;
    requests.get(key)?.abort();
    const controller = new AbortController();
    requests.set(key, controller);
    state.loading[key] = true;
    state.error = null;
    const current = () =>
      epoch === generation &&
      requests.get(key) === controller &&
      !controller.signal.aborted;
    try {
      const response = await action(accountId, controller.signal);
      if (!current()) return null;
      const data = response.data;
      if (
        data.contract_version !== 1 ||
        data.source !== 'glpi' ||
        data.account_id !== accountId ||
        data.user_id !== userId
      )
        throw new Error('Invalid GLPI response');
      state.data[key] = data;
      if (key === 'context') state.context = data;
      return data;
    } catch (error) {
      if (current()) {
        delete state.data[key];
        const code = error.response?.data?.source_code;
        state.error = {
          status: error.response?.status || 0,
          code:
            typeof code === 'string'
              ? code
              : error.response?.data?.code || 'source_unavailable',
        };
      }
      return null;
    } finally {
      if (current()) state.loading[key] = false;
    }
  };
  const read = (key, path, params) =>
    run(key, (account, signal) => API.get(account, path, params, signal));
  return { session, state, read, run, clear, API };
}
