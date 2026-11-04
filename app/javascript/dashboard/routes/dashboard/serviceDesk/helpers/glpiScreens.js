// UI choices describe routes; authenticated backend context remains the authority.
const localScreens = new Set([
  'glpi_settings',
  'settings',
  'priorities',
  'categories',
  'ticket_types',
  'statuses',
  'units',
  'operator_companies',
  'automations',
  'native_history',
]);
const resources = {
  queues: 'groups',
  assignees: 'users',
  catalog: 'templates',
  knowledge: 'knowledge',
  tasks: 'tasks',
  approvals: 'validations',
  problems: 'problems',
  changes: 'changes',
  assets: 'assets',
  documents: 'documents',
  surveys: 'satisfaction',
};
export const usesGlpiScreen = (context, screen) =>
  context?.data_source === 'glpi' && !localScreens.has(screen);
export const isJrcConfiguration = screen =>
  localScreens.has(screen) &&
  screen !== 'native_history' &&
  screen !== 'glpi_settings';
export function glpiScreen(screen) {
  const filters = {};
  if (screen === 'mine') filters.mine = true;
  if (screen === 'incidents') filters.type = 1;
  if (['glpi', 'tickets', 'mine', 'incidents'].includes(screen))
    return {
      kind: 'tickets',
      filters,
    };
  if (['overview', 'reports', 'sla'].includes(screen))
    return { kind: 'overview' };
  if (['detail', 'edit', 'new'].includes(screen)) return { kind: 'ticket' };
  if (resources[screen])
    return { kind: 'resource', resource: resources[screen] };
  return null;
}
export function operationBlock(descriptor) {
  if (!descriptor.supported) return 'unsupported';
  if (!descriptor.permitted) return 'jrc_denied';
  if (descriptor.source_allowed === false) return 'source_denied';
  return null;
}
export const operationAttributes = (descriptor, values) =>
  Object.fromEntries(
    descriptor.fields
      .filter(
        field =>
          values[field] !== '' &&
          values[field] !== undefined &&
          values[field] !== null
      )
      .map(field => [field, values[field]])
  );
export const operationFamily = resource =>
  ({
    tickets: 'ticket',
    tasks: 'task',
    followups: 'followup',
    solutions: 'ticket',
    validations: 'validation',
    actors: 'actor',
    actor_groups: 'group',
    actor_suppliers: 'supplier',
    documents: 'document_link',
    assets: 'asset',
    problem_links: 'problem_link',
    change_links: 'change_link',
    knowledge_links: 'knowledge_link',
    problems: 'problem',
    changes: 'change',
    knowledge: 'knowledge',
    categories: 'category',
    templates: 'template',
    template_mandatory: 'template_mandatory',
    template_hidden: 'template_hidden',
    template_predefined: 'template_predefined',
  })[resource] || null;
export const fieldResource = field =>
  ({
    itilcategories_id: 'categories',
    users_id: 'users',
    users_id_tech: 'users',
    users_id_validate: 'users',
    _users_id_assign: 'users',
    _users_id_requester: 'users',
    groups_id: 'groups',
    groups_id_tech: 'groups',
    _groups_id_assign: 'groups',
    num: 'ticket_fields',
    suppliers_id: 'suppliers',
    solutiontypes_id: 'solution_types',
    taskcategories_id: 'task_categories',
    problems_id: 'problems',
    changes_id: 'changes',
    knowbaseitems_id: 'knowledge',
    tickettemplates_id: 'templates',
    knowbaseitemcategories_id: null,
  })[field];
export const numericField = field =>
  /(^_|_)id($|_)/.test(field) ||
  [
    'type',
    'urgency',
    'impact',
    'priority',
    'status',
    'state',
    'actiontime',
    'is_private',
    'is_faq',
    'is_recursive',
    'is_incident',
    'is_request',
    'is_problem',
    'is_change',
    'num',
  ].includes(field);
