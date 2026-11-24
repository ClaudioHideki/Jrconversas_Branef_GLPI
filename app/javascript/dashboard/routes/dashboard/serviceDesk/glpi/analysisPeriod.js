export function analysisPeriod(from, through) {
  const date = value => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
    const parsed = new Date(`${value}T00:00:00Z`);
    return !Number.isNaN(parsed.getTime()) &&
      parsed.toISOString().slice(0, 10) === value
      ? parsed
      : null;
  };
  const start = date(from);
  const end = date(through);
  if (!start || !end || start > end) return null;
  end.setUTCDate(end.getUTCDate() + 1);
  if (end - start > 62 * 86400000) return null;
  return { from, to: end.toISOString().slice(0, 10) };
}
