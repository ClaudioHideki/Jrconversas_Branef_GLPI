/* global axios */
import { canonicalId } from 'dashboard/routes/dashboard/serviceDesk/helpers/access';

const base = accountId => {
  const id = canonicalId(accountId);
  if (!id) throw new Error('Invalid account');
  return `/api/v1/accounts/${id}/jrc_service_desk/glpi`;
};
export default {
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
