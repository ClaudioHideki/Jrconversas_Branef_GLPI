import { onBeforeUnmount, reactive, watch } from 'vue';
import { createServiceDeskGlpiClient } from 'dashboard/api/serviceDeskGlpi';
import { useServiceDesk } from '../composables/useServiceDesk';
import { glpiBinding, sameGlpiBinding } from '../helpers/glpiBinding';

export function useGlpi() {
  const session = useServiceDesk();
  const state = reactive({
    context: null,
    error: null,
    errors: {},
    loading: {},
    data: {},
  });
  const binding = () =>
    glpiBinding(
      session.state.context?.connection_id != null
        ? session.state.context
        : state.context
    );
  const API = createServiceDeskGlpiClient(binding);
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
    [
      session.accountId,
      session.userId,
      () => session.state.status,
      () => session.state.context?.data_source,
      () => session.state.context?.connection_id,
      () => session.state.context?.connection_version,
    ],
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
        !['configuration', 'validate'].includes(key) &&
        binding() &&
        !sameGlpiBinding(binding(), glpiBinding(data))
      ) {
        throw Object.assign(new Error('GLPI configuration changed'), {
          code: 'configuration_changed',
          status: 409,
        });
      }
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
          status: error.response?.status || error.status || 0,
          code:
            typeof code === 'string'
              ? code
              : body?.code || error.code || 'source_unavailable',
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
  return { session, state, read, run, clear, discard, binding, API };
}
