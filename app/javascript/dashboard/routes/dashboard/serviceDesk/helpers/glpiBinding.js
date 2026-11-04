import { canonicalId } from './access';

export function glpiBinding(value) {
  if (value?.connection_id == null && value?.connection_version == null)
    return null;
  const connectionId = canonicalId(value?.connection_id);
  const version = value?.connection_version;
  if (!connectionId || !Number.isInteger(version) || version < 0)
    throw new Error('Invalid GLPI connection reference');
  return { connection_id: connectionId, connection_version: version };
}
export const sameGlpiBinding = (left, right) =>
  left?.connection_id === right?.connection_id &&
  left?.connection_version === right?.connection_version;
export function serviceDeskSourceChanged(previous, next) {
  if (!previous || !next) return false;
  if (previous.data_source !== next.data_source) return true;
  return (
    next.data_source === 'glpi' &&
    !sameGlpiBinding(glpiBinding(previous), glpiBinding(next))
  );
}
export function commandMatchesBinding(command, binding) {
  if (!binding) return true;
  try {
    return sameGlpiBinding(glpiBinding(command), binding);
  } catch {
    return false;
  }
}
