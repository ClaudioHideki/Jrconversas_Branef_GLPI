/* global axios */
import { canonicalId } from 'dashboard/routes/dashboard/serviceDesk/helpers/access';
import { glpiBinding } from 'dashboard/routes/dashboard/serviceDesk/helpers/glpiBinding';

const base = accountId => {
  const id = canonicalId(accountId);
  if (!id) throw new Error('Invalid account');
  return `/api/v1/accounts/${id}/jrc_service_desk/glpi`;
};
export function createServiceDeskGlpiClient(scope = () => null) {
  const headers = () => {
    const binding = glpiBinding(scope());
    if (!binding) return {};
    return {
      'X-JRC-GLPI-Connection-Id': binding.connection_id,
      'X-JRC-GLPI-Connection-Version': String(binding.connection_version),
    };
  };
  return {
    startSync(accountId, signal) {
      return axios.post(
        `${base(accountId)}/sync`,
        {},
        { signal, timeout: 30000, headers: headers() }
      );
    },
    cancelSync(accountId, id, signal) {
      return axios.post(
        `${base(accountId)}/sync/${canonicalId(id)}/cancel`,
        {},
        { signal, timeout: 30000, headers: headers() }
      );
    },
    execute(accountId, values, signal) {
      return axios.post(`${base(accountId)}/operations`, values, {
        signal,
        headers: headers(),
        timeout: 120000,
      });
    },
    startExport(accountId, values, signal) {
      return axios.post(`${base(accountId)}/exports`, values, {
        signal,
        headers: headers(),
        timeout: 30000,
      });
    },
    cancelExport(accountId, id, signal) {
      return axios.post(
        `${base(accountId)}/exports/${canonicalId(id)}/cancel`,
        {},
        { signal, timeout: 30000, headers: headers() }
      );
    },
    downloadExport(accountId, id, signal) {
      return axios.get(
        `${base(accountId)}/exports/${canonicalId(id)}/download`,
        {
          signal,
          headers: headers(),
          responseType: 'blob',
          timeout: 120000,
        }
      );
    },
    uploadDocument(accountId, ticketId, values, signal) {
      return axios.post(
        `${base(accountId)}/tickets/${canonicalId(ticketId)}/documents`,
        values,
        { signal, timeout: 120000, headers: headers() }
      );
    },
    downloadDocument(accountId, ticketId, documentId, signal) {
      return axios.get(
        `${base(accountId)}/tickets/${canonicalId(ticketId)}/documents/${canonicalId(documentId)}/download`,
        { signal, responseType: 'blob', timeout: 120000, headers: headers() }
      );
    },
    get(accountId, path, params, signal) {
      return axios.get(`${base(accountId)}/${path}`, {
        params,
        signal,
        headers: ['context', 'connection', 'connection/validate'].includes(path)
          ? {}
          : headers(),
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
      return axios.post(`${base(accountId)}/tickets`, values, {
        timeout: 90000,
        headers: headers(),
      });
    },
    reconcile(accountId, id, values) {
      return axios.post(`${base(accountId)}/commands/${id}/reconcile`, values, {
        timeout: 90000,
        headers: headers(),
      });
    },
    export(accountId, params) {
      return axios.get(`${base(accountId)}/reports/export`, {
        params,
        headers: headers(),
        responseType: 'blob',
        timeout: 120000,
      });
    },
  };
}
export default createServiceDeskGlpiClient();
