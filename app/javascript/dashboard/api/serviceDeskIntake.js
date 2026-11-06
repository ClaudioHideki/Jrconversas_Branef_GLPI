/* global axios */
import { canonicalId } from 'dashboard/routes/dashboard/serviceDesk/helpers/access';

const base = accountId => {
  const id = canonicalId(accountId);
  if (!id) throw new Error('Invalid account');
  return `/api/v1/accounts/${id}/jrc_service_desk/intake`;
};
export default {
  inboxes: (accountId, signal) => axios.get(`${base(accountId)}/inboxes`, { signal }),
  get: (accountId, inboxId, signal) => axios.get(`${base(accountId)}/configuration`, { params: { inbox_id: canonicalId(inboxId) }, signal }),
  preview: (accountId, values, signal) => axios.post(`${base(accountId)}/readiness`, values, { signal, timeout: 120000 }),
  publish: (accountId, values, signal) => axios.post(`${base(accountId)}/configuration`, values, { signal, timeout: 120000 }),
  demands: (accountId, conversationId, signal) => axios.get(`${base(accountId)}/conversations/${canonicalId(conversationId)}`, { signal }),
  notice: (accountId, demandId, values, signal) => axios.post(`${base(accountId)}/demands/${canonicalId(demandId)}/notice`, values, { signal }),
  complete: (accountId, demandId, values, signal) => axios.post(`${base(accountId)}/demands/${canonicalId(demandId)}/complete`, values, { signal, timeout: 120000 }),
};
