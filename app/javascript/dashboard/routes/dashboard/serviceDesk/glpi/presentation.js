import { zonedTimeToUtc } from 'date-fns-tz';

export const plainText = value => {
  const node = document.createElement('textarea');
  node.innerHTML = String(value ?? '');
  return node.value;
};

export const formatGlpiDate = (value, timezone) => {
  if (!value) return '—';
  const naive = /^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}$/.test(value);
  if (naive && !timezone) return value;
  const date = naive ? zonedTimeToUtc(value, timezone) : new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: timezone || 'UTC',
  }).format(date);
};

export const groupErrors = errors => {
  const groups = new Map();
  Object.entries(errors || {}).forEach(([operation, error]) => {
    if (!error) return;
    const code = error.code || 'source_unavailable';
    if (!groups.has(code)) groups.set(code, { code, operations: [] });
    groups.get(code).operations.push(operation);
  });
  return [...groups.values()];
};

export const selectedFilters = query =>
  Object.fromEntries(
    Object.entries(query || {}).filter(
      ([key, value]) =>
        ['entity_id', 'search', 'status', 'priority', 'from', 'to'].includes(
          key
        ) &&
        ['string', 'number'].includes(typeof value) &&
        String(value) !== ''
    )
  );

export const badgeTone = (kind, value) => {
  const tones =
    kind === 'status'
      ? { 1: 'blue', 2: 'blue', 3: 'violet', 4: 'amber', 5: 'teal', 6: 'teal' }
      : { 1: 'slate', 2: 'slate', 3: 'blue', 4: 'amber', 5: 'ruby', 6: 'ruby' };
  const colors = {
    blue: 'border-n-blue-6 bg-n-blue-2 text-n-blue-11',
    violet: 'border-n-violet-6 bg-n-violet-2 text-n-violet-11',
    amber: 'border-n-amber-6 bg-n-amber-2 text-n-amber-11',
    teal: 'border-n-teal-6 bg-n-teal-2 text-n-teal-11',
    ruby: 'border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11',
    slate: 'border-n-weak bg-n-slate-2 text-n-slate-11',
  };
  return colors[tones[value] || 'slate'];
};
