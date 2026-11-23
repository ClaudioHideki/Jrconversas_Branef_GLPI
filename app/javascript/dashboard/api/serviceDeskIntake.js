/* global axios */
import { canonicalId } from 'dashboard/routes/dashboard/serviceDesk/helpers/access';

const base = accountId => {
  const id = canonicalId(accountId);
  if (!id) throw new Error('Invalid account');
  return `/api/v1/accounts/${id}/jrc_service_desk/intake`;
};
const pollDelay = signal =>
  new Promise((resolve, reject) => {
    signal.throwIfAborted();
    let timer;
    const abort = () => {
      clearTimeout(timer);
      reject(signal.reason);
    };
    timer = setTimeout(() => {
      signal.removeEventListener('abort', abort);
      resolve();
    }, 3000);
    signal.addEventListener('abort', abort, { once: true });
  });

const runOperation = async (accountId, kind, values, signal) => {
  const url = `${base(accountId)}/operations`;
  const options = { signal, timeout: 15000 };
  const { data: started } = await axios.post(`${url}/${kind}`, values, options);
  const { operation_id: operationId, user_id: userId } = started;
  if (
    started.account_id !== canonicalId(accountId) ||
    !canonicalId(userId) ||
    typeof operationId !== 'string' ||
    !/^[a-f0-9-]{36}$/.test(operationId) ||
    started.state !== 'queued'
  ) {
    throw new Error('Invalid intake operation');
  }

  const poll = async () => {
    await pollDelay(signal);
    const { data } = await axios.get(`${url}/${operationId}`, options);
    if (
      data.operation_id !== operationId ||
      data.account_id !== started.account_id ||
      data.user_id !== userId
    ) {
      throw new Error('Stale scope');
    }
    if (data.state === 'queued') return poll();
    if (data.state === 'failed') throw new Error(data.error);
    if (data.state !== 'completed' || !data.result)
      throw new Error('Invalid intake result');
    return {
      data: {
        ...data.result,
        account_id: data.account_id,
        user_id: data.user_id,
      },
    };
  };
  return poll();
};

export default {
  inboxes: (accountId, signal) =>
    axios.get(`${base(accountId)}/inboxes`, { signal }),
  get: (accountId, inboxId, signal) =>
    axios.get(`${base(accountId)}/configuration`, {
      params: { inbox_id: canonicalId(inboxId) },
      signal,
    }),
  preview: (accountId, values, signal) =>
    runOperation(accountId, 'readiness', values, signal),
  publish: (accountId, values, signal) =>
    runOperation(accountId, 'publish', values, signal),
  demands: (accountId, conversationId, signal) =>
    axios.get(
      `${base(accountId)}/conversations/${canonicalId(conversationId)}`,
      { signal }
    ),
  notice: (accountId, demandId, values, signal) =>
    axios.post(
      `${base(accountId)}/demands/${canonicalId(demandId)}/notice`,
      values,
      { signal }
    ),
  complete: (accountId, demandId, values, signal) =>
    axios.post(
      `${base(accountId)}/demands/${canonicalId(demandId)}/complete`,
      values,
      { signal, timeout: 120000 }
    ),
};
