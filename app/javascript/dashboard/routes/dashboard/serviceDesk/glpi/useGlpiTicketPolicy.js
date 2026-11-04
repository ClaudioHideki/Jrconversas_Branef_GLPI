import { computed, onBeforeUnmount, ref, watch } from 'vue';

const supportedFields = new Set([
  'name',
  'content',
  'type',
  'urgency',
  'impact',
  'priority',
  'itilcategories_id',
  '_users_id_requester',
  'status',
]);
const text = (value, rich = false) => {
  if (!rich)
    return String(value ?? '')
      .replace(/\s+/g, ' ')
      .trim();
  const element = document.createElement('div');
  element.innerHTML = value || '';
  return (element.textContent || '').replace(/\s+/g, ' ').trim();
};

// Only the authenticated primary-source ticket.create path uses this policy.
export function useGlpiTicketPolicy({ glpi, active, entityId, values, rich }) {
  const form = ref(null);
  const templateId = ref('');
  const pending = ref(false);
  const failed = ref(false);
  let generation = 0;
  let applying = false;
  let previousEntity = '';
  let defaults = {};
  let used = false;
  const limitations = computed(() => [
    ...(form.value?.unsupported_required || []),
    ...(form.value?.fields || []).filter(field => !supportedFields.has(field)),
    ...(form.value?.required || []).filter(
      field => !supportedFields.has(field)
    ),
  ]);
  const available = computed(
    () =>
      !!form.value &&
      form.value.supported === true &&
      /^[a-f0-9]{64}$/.test(form.value.version || '') &&
      !limitations.value.length
  );
  const fields = computed(() =>
    (
      form.value?.fields ||
      (entityId.value === '' ? ['type'] : ['type', 'itilcategories_id'])
    ).filter(
      field =>
        supportedFields.has(field) && !form.value?.hidden?.includes(field)
    )
  );
  const required = computed(() => form.value?.required || []);
  const missing = computed(() =>
    required.value.filter(field => {
      if (form.value?.hidden?.includes(field)) return false;
      if (['name', 'content'].includes(field))
        return !text(values[field], rich[field]);
      return (
        values[field] === '' ||
        values[field] == null ||
        Number(values[field]) <= 0
      );
    })
  );
  const placeholder = computed(() => {
    if (
      !required.value.includes('content') ||
      form.value?.hidden?.includes('content')
    )
      return false;
    const originalHtml = form.value?.predefined_html?.content;
    const original = originalHtml ?? form.value?.predefined?.content;
    return (
      !!text(original, !!originalHtml) &&
      text(values.content, rich.content) === text(original, !!originalHtml)
    );
  });
  const blocked = computed(
    () =>
      !available.value ||
      pending.value ||
      missing.value.length > 0 ||
      placeholder.value
  );
  const load = async () => {
    if (applying) return;
    if (!active.value && !used) return;
    used = true;
    generation += 1;
    const epoch = generation;
    glpi.discard('ticket_form');
    pending.value = false;
    failed.value = false;
    if (!active.value) {
      form.value = null;
      defaults = {};
      return;
    }
    applying = true;
    if (String(entityId.value) !== previousEntity) {
      templateId.value = '';
      ['itilcategories_id', '_users_id_requester'].forEach(field => {
        values[field] = '';
      });
      form.value = null;
      previousEntity = String(entityId.value);
    }
    if (!values.type) values.type = 1;
    applying = false;
    if (entityId.value === '') {
      form.value = null;
      defaults = {};
      return;
    }
    pending.value = true;
    const response = await glpi.read('ticket_form', 'ticket_form', {
      entity_id: Number(entityId.value),
      type: Number(values.type),
      ...(values.itilcategories_id
        ? { category_id: Number(values.itilcategories_id) }
        : {}),
      ...(templateId.value ? { template_id: Number(templateId.value) } : {}),
    });
    if (epoch !== generation) return;
    pending.value = false;
    if (
      !response?.form ||
      !Array.isArray(response.form.fields) ||
      !Array.isArray(response.form.required) ||
      !Array.isArray(response.form.hidden)
    ) {
      form.value = null;
      failed.value = true;
      return;
    }
    const resolved = response.form;
    applying = true;
    const nextDefaults = {};
    supportedFields.forEach(field => {
      const html =
        field === 'content' ? resolved.predefined_html?.content : null;
      let value = html ?? resolved.predefined?.[field] ?? '';
      if (field === 'type') value = resolved.type;
      if (field === 'itilcategories_id') value = resolved.category_id ?? '';
      nextDefaults[field] = value;
      if (
        resolved.hidden.includes(field) ||
        values[field] === '' ||
        values[field] == null ||
        String(values[field]) === String(defaults[field]) ||
        ['type', 'itilcategories_id'].includes(field)
      ) {
        values[field] = value;
        rich[field] = !!html;
      }
    });
    defaults = nextDefaults;
    form.value = resolved;
    applying = false;
  };
  watch(
    [
      active,
      entityId,
      () => values.type,
      () => values.itilcategories_id,
      templateId,
      () => glpi.session?.accountId.value,
      () => glpi.session?.userId.value,
      () => glpi.session?.state.status,
      () => glpi.session?.state.context?.connection_id,
      () => glpi.session?.state.context?.connection_version,
    ],
    (current, previous) => {
      if (applying) return;
      if (
        (active.value || used) &&
        previous.length &&
        current.slice(5).some((value, index) => value !== previous[index + 5])
      ) {
        applying = true;
        entityId.value = '';
        templateId.value = '';
        Object.keys(values).forEach(field => {
          values[field] = '';
        });
        Object.keys(rich).forEach(field => {
          rich[field] = false;
        });
        defaults = {};
        previousEntity = '';
        form.value = null;
        applying = false;
      }
      load();
    },
    { immediate: true, flush: 'sync' }
  );
  onBeforeUnmount(() => {
    generation += 1;
    if (used) glpi.discard('ticket_form');
  });
  return {
    form,
    fields,
    required,
    templateId,
    pending,
    failed,
    limitations,
    available,
    missing,
    placeholder,
    blocked,
    load,
  };
}
