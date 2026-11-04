/* global axios */
import { canonicalId } from 'dashboard/routes/dashboard/serviceDesk/helpers/access';

const base = accountId => {
  const id = canonicalId(accountId);
  if (!id) throw new Error('Invalid account');
  return `/api/v1/accounts/${id}/jrc_service_desk/glpi`;
};
export default {
  startSync(accountId, signal) {
    return axios.post(
      `${base(accountId)}/sync`,
      {},
      { signal, timeout: 30000 }
    );
  },
  cancelSync(accountId, id, signal) {
    return axios.post(
      `${base(accountId)}/sync/${canonicalId(id)}/cancel`,
      {},
      { signal, timeout: 30000 }
    );
  },
  execute(accountId, values, signal) {
    return axios.post(`${base(accountId)}/operations`, values, {
      signal,
      timeout: 120000,
    });
  },
  startExport(accountId, values, signal) {
    return axios.post(`${base(accountId)}/exports`, values, {
      signal,
      timeout: 30000,
    });
  },
  cancelExport(accountId, id, signal) {
    return axios.post(
      `${base(accountId)}/exports/${canonicalId(id)}/cancel`,
      {},
      { signal, timeout: 30000 }
    );
  },
  downloadExport(accountId, id, signal) {
    return axios.get(`${base(accountId)}/exports/${canonicalId(id)}/download`, {
      signal,
      responseType: 'blob',
      timeout: 120000,
    });
  },
  uploadDocument(accountId, ticketId, values, signal) {
    return axios.post(
      `${base(accountId)}/tickets/${canonicalId(ticketId)}/documents`,
      values,
      { signal, timeout: 120000 }
    );
  },
  downloadDocument(accountId, ticketId, documentId, signal) {
    return axios.get(
      `${base(accountId)}/tickets/${canonicalId(ticketId)}/documents/${canonicalId(documentId)}/download`,
      { signal, responseType: 'blob', timeout: 120000 }
    );
  },
  get(accountId, path, params, signal) {
    return axios.get(`${base(accountId)}/${path}`, {
      params,
      signal,
      timeout: 120000,
    });
  },
  save(accountId, values) {
    return axios.patch(`${base(accountId)}/connection`, values, {
      timeout: 45000,
    });
  },
  validate(accountId) {
    return axios.post(
      `${base(accountId)}/connection/validate`,
      {},
      { timeout: 90000 }
    );
  },
  create(accountId, values) {
    return axios.post(`${base(accountId)}/tickets`, values, { timeout: 90000 });
  },
  reconcile(accountId, id, values) {
    return axios.post(`${base(accountId)}/commands/${id}/reconcile`, values, {
      timeout: 90000,
    });
  },
  export(accountId, params) {
    return axios.get(`${base(accountId)}/reports/export`, {
      params,
      responseType: 'blob',
      timeout: 120000,
    });
  },
};
