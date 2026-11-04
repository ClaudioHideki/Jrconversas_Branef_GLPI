import { onBeforeUnmount, reactive, watch } from 'vue';
import API from 'dashboard/api/serviceDeskGlpi';
import { useServiceDesk } from '../composables/useServiceDesk';

export function useGlpi() {
  const session = useServiceDesk();
  const state = reactive({
    context: null,
    error: null,
    errors: {},
    loading: {},
    data: {},
  });
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
    state.errors = {};
  };
  watch(
    [session.accountId, session.userId, () => session.state.status],
    clear,
    { flush: 'sync' }
  );
  onBeforeUnmount(clear);
  const run = async (key, action, options = {}) => {
    const epoch = generation;
    const accountId = session.accountId.value;
    const userId = session.userId.value;
    requests.get(key)?.abort();
    const controller = new AbortController();
    requests.set(key, controller);
    state.loading[key] = true;
    state.error = null;
    delete state.errors[key];
    const current = () =>
      epoch === generation &&
      requests.get(key) === controller &&
      !controller.signal.aborted;
    try {
      const response = await action(accountId, controller.signal);
      if (!current()) return null;
      if (
        options.binary &&
        response.data instanceof Blob &&
        response.status !== 202 &&
        !response.data.type.includes('json')
      ) {
        if (response.data.size > options.maxBytes)
          throw new Error('File limit');
        return { binary: response.data };
      }
      const data =
        response.data instanceof Blob
          ? JSON.parse(await response.data.text())
          : response.data;
      if (!current()) return null;
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
      let body = error.response?.data;
      if (body instanceof Blob && body.type.includes('json')) {
        try {
          body = JSON.parse(await body.text());
        } catch {
          body = null;
        }
      }
      if (current()) {
        delete state.data[key];
        if (key === 'context') state.context = null;
        const code = body?.source_code;
        state.error = {
          status: error.response?.status || 0,
          code:
            typeof code === 'string'
              ? code
              : body?.code || 'source_unavailable',
        };
        state.errors[key] = state.error;
      }
      return null;
    } finally {
      if (current()) state.loading[key] = false;
    }
  };
  const read = (key, path, params) =>
    run(key, (account, signal) => API.get(account, path, params, signal));
  const discard = key => {
    requests.get(key)?.abort();
    requests.delete(key);
    delete state.data[key];
    delete state.errors[key];
    state.loading[key] = false;
  };
  return { session, state, read, run, clear, discard, API };
}
