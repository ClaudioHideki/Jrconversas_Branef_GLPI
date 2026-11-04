<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import { useGlpi } from './useGlpi';

const { t } = useI18n();
const glpi = useGlpi();
const { state, session, read, run, API } = glpi;
const form = reactive({
  base_url: '',
  timezone: 'America/Sao_Paulo',
  enabled: false,
  primary_source: 'native',
  user_token: '',
  app_token: '',
  entity_mappings: [],
  user_mappings: [],
  lock_version: 0,
});
const categories = ref([]);
const saved = ref(false);
const validation = ref(null);
const defaultUnit = ref('');
const reconcile = reactive({ command_id: '', remote_id: '' });
const busy = computed(() => Object.values(state.loading).some(Boolean));
const configuration = computed(() => state.data.configuration);
const apply = payload => {
  Object.assign(form, payload.connection, { user_token: '', app_token: '' });
  categories.value = (payload.connection.categories || []).map(row => ({
    ...row,
  }));
  defaultUnit.value = payload.units[0]?.id || '';
};
watch(
  () => session.state.status,
  async status => {
    if (status !== 'ready') return;
    const value = await read('configuration', 'connection');
    if (value) apply(value);
  },
  { immediate: true }
);
const save = async () => {
  saved.value = false;
  validation.value = null;
  const values = {
    base_url: form.base_url,
    timezone: form.timezone,
    enabled: form.enabled,
    primary_source: form.primary_source,
    entity_mappings: form.entity_mappings,
    user_mappings: form.user_mappings,
    categories: categories.value.map(row => ({
      id: Number(row.id),
      name: row.name,
      entity_id: Number(row.entity_id),
    })),
    lock_version: form.lock_version,
  };
  if (form.user_token) values.user_token = form.user_token;
  if (form.app_token) values.app_token = form.app_token;
  const result = await run('configuration', account =>
    API.save(account, values)
  );
  if (result) {
    apply(result);
    saved.value = true;
  }
};
const validate = async () => {
  validation.value = await run('validate', account => API.validate(account));
};
const mapEntities = () => {
  if (!defaultUnit.value || !validation.value) return;
  form.entity_mappings = validation.value.entities.map(row => ({
    entity_id: row.id,
    unit_id: Number(defaultUnit.value),
  }));
};
const entityName = id =>
  validation.value?.entities?.find(row => String(row.id) === String(id))
    ?.name || t('JRC_GLPI.entity_number', { id });
const reconcileCommand = async () => {
  if (
    !/^[1-9]\d*$/.test(reconcile.command_id) ||
    !/^[1-9]\d*$/.test(reconcile.remote_id)
  )
    return;
  await run('reconcile', account =>
    API.reconcile(account, reconcile.command_id, {
      remote_id: reconcile.remote_id,
    })
  );
};
</script>

<template>
  <section
    class="grid gap-4"
    data-testid="glpi-settings"
  >
    <header>
      <h2 class="text-xl font-semibold">
        {{ t('JRC_GLPI.configure') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('JRC_GLPI.settings_help') }}
      </p>
    </header>
    <p
      v-if="state.error"
      class="rounded-lg border border-n-ruby-6 bg-n-ruby-2 p-4 text-sm"
      role="alert"
    >
      {{ t('JRC_GLPI.error') }}
      {{ t('JRC_GLPI.source_code', { code: state.error.code }) }}
    </p>
    <p
      v-if="saved"
      class="rounded-lg bg-n-teal-2 p-3 text-sm"
      role="status"
    >
      {{ t('JRC_GLPI.saved') }}
    </p>
    <form
      v-if="configuration"
      class="grid gap-4"
      @submit.prevent="save"
    >
      <Panel :title="t('JRC_GLPI.connection')">
        <div class="grid gap-4 md:grid-cols-2">
          <label class="grid gap-1 text-sm md:col-span-2">
            {{ t('JRC_GLPI.endpoint') }}
            <input
              v-model="form.base_url"
              type="url"
              required
              class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
            />
          </label>
          <label
            v-for="field in ['user_token', 'app_token']"
            :key="field"
            class="grid gap-1 text-sm"
          >
            {{ t(`JRC_GLPI.${field}`) }}
            <input
              v-model="form[field]"
              type="password"
              autocomplete="new-password"
              :required="!configuration.connection[`${field}_configured`]"
              :placeholder="
                configuration.connection[`${field}_configured`]
                  ? t('JRC_GLPI.credential_set')
                  : ''
              "
              class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
            />
          </label>
          <label class="grid gap-1 text-sm">
            {{ t('JRC_GLPI.timezone') }}
            <input
              v-model="form.timezone"
              required
              class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
            />
          </label>
          <label class="flex items-center gap-2 text-sm">
            <input
              v-model="form.enabled"
              type="checkbox"
            />
            {{ t('JRC_GLPI.enable') }}
          </label>
          <label class="grid gap-1 text-sm">
            {{ t('JRC_GLPI.workspace.primary_source') }}
            <select
              v-model="form.primary_source"
              data-testid="glpi-primary-source"
              class="!mb-0 h-10 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
            >
              <option value="native">
                {{ t('JRC_GLPI.workspace.source_native') }}
              </option>
              <option value="glpi">
                {{ t('JRC_GLPI.workspace.source_glpi') }}
              </option>
            </select>
          </label>
          <p class="text-xs text-n-slate-11">
            {{ t('JRC_GLPI.workspace.primary_source_help') }}
          </p>
        </div>
        <div class="mt-4 flex flex-wrap gap-2">
          <Button
            type="submit"
            :label="t('JRC_SERVICE_DESK.COMMON.save')"
            :disabled="busy"
          />
          <Button
            type="button"
            :label="t('JRC_GLPI.validate')"
            variant="outline"
            :disabled="busy || !configuration.connection.configured"
            @click="validate"
          />
        </div>
        <div
          v-if="validation"
          class="mt-4 grid gap-2 rounded-lg bg-n-teal-2 p-3 text-sm"
          role="status"
        >
          <p>
            {{
              t('JRC_GLPI.connected', {
                profile: validation.profile.name,
              })
            }}
          </p>
          <p>
            {{
              t(
                validation.can_create
                  ? 'JRC_GLPI.create_allowed'
                  : 'JRC_GLPI.create_denied'
              )
            }}
          </p>
          <p>
            {{
              t(
                validation.can_read_all
                  ? 'JRC_GLPI.read_all_allowed'
                  : 'JRC_GLPI.read_limited'
              )
            }}
          </p>
        </div>
      </Panel>
      <Panel :title="t('JRC_GLPI.entity_mapping')">
        <p class="mb-3 text-sm text-n-slate-11">
          {{ t('JRC_GLPI.entity_mapping_help') }}
        </p>
        <div
          v-if="validation"
          class="mb-4 flex flex-wrap items-center gap-2"
        >
          <select
            v-model="defaultUnit"
            class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
            :aria-label="t('JRC_GLPI.unit')"
          >
            <option
              v-for="unit in configuration.units"
              :key="unit.id"
              :value="unit.id"
            >
              {{ unit.name }}
            </option>
          </select>
          <Button
            type="button"
            :label="t('JRC_GLPI.map_entities')"
            variant="outline"
            :disabled="!defaultUnit"
            @click="mapEntities"
          />
        </div>
        <div class="grid gap-2">
          <div
            v-for="(mapping, index) in form.entity_mappings"
            :key="mapping.entity_id"
            class="grid grid-cols-[1fr_1fr_auto] items-center gap-2"
          >
            <span class="text-sm">{{ entityName(mapping.entity_id) }}</span>
            <select
              v-model.number="mapping.unit_id"
              class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
              :aria-label="t('JRC_GLPI.unit')"
            >
              <option
                v-for="unit in configuration.units"
                :key="unit.id"
                :value="unit.id"
              >
                {{ unit.name }}
              </option>
            </select>
            <Button
              type="button"
              icon="i-lucide-x"
              :aria-label="t('JRC_GLPI.remove')"
              variant="ghost"
              @click="form.entity_mappings.splice(index, 1)"
            />
          </div>
        </div>
      </Panel>
      <Panel :title="t('JRC_GLPI.user_mapping')">
        <p class="mb-3 text-sm text-n-slate-11">
          {{ t('JRC_GLPI.user_mapping_help') }}
        </p>
        <div class="grid gap-2">
          <div
            v-for="(mapping, index) in form.user_mappings"
            :key="index"
            class="grid grid-cols-[1fr_1fr_auto] items-center gap-2"
          >
            <select
              v-model.number="mapping.account_user_id"
              class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
              :aria-label="t('JRC_GLPI.member')"
            >
              <option
                v-for="member in configuration.members"
                :key="member.id"
                :value="member.id"
              >
                {{ member.name }}
              </option>
            </select>
            <input
              v-model.number="mapping.glpi_user_id"
              type="number"
              min="1"
              required
              :aria-label="t('JRC_GLPI.remote_user')"
              class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
            />
            <Button
              type="button"
              icon="i-lucide-x"
              :aria-label="t('JRC_GLPI.remove')"
              variant="ghost"
              @click="form.user_mappings.splice(index, 1)"
            />
          </div>
        </div>
        <Button
          type="button"
          class="mt-3"
          :label="t('JRC_SERVICE_DESK.COMMON.add')"
          variant="outline"
          @click="
            form.user_mappings.push({
              account_user_id: configuration.members[0]?.id || '',
              glpi_user_id: '',
            })
          "
        />
      </Panel>
      <Panel :title="t('JRC_GLPI.category_mapping')">
        <p class="mb-3 text-sm">
          {{ t('JRC_GLPI.workspace.category_mapping_help') }}
        </p>
        <div
          v-for="(category, index) in categories"
          :key="index"
          class="mb-3 grid gap-3 md:grid-cols-4"
        >
          <label class="grid gap-1 text-xs">
            {{ t('JRC_GLPI.category') }}
            <input
              v-model="category.id"
              type="number"
              min="1"
              required
              class="!mb-0 rounded-lg border border-n-weak px-3 py-2 text-sm"
            />
          </label>
          <label class="grid gap-1 text-xs">
            {{ t('JRC_GLPI.fields.name') }}
            <input
              v-model="category.name"
              required
              class="!mb-0 rounded-lg border border-n-weak px-3 py-2 text-sm"
            />
          </label>
          <label class="grid gap-1 text-xs">
            {{ t('JRC_GLPI.entity') }}
            <select
              v-model="category.entity_id"
              required
              class="!mb-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
            >
              <option value="">
                {{ t('JRC_SERVICE_DESK.COMMON.select') }}
              </option>
              <option
                v-for="mapping in form.entity_mappings"
                :key="mapping.entity_id"
                :value="mapping.entity_id"
              >
                {{ entityName(mapping.entity_id) }}
              </option>
            </select>
          </label>
          <Button
            type="button"
            :label="t('JRC_GLPI.remove')"
            variant="outline"
            @click="categories.splice(index, 1)"
          />
        </div>
        <Button
          type="button"
          :label="t('JRC_GLPI.workspace.add_category')"
          variant="outline"
          @click="categories.push({ id: '', name: '', entity_id: '' })"
        />
      </Panel>
      <div>
        <Button
          type="submit"
          :label="t('JRC_SERVICE_DESK.COMMON.save')"
          :disabled="busy"
        />
      </div>
    </form>
    <Panel
      v-if="configuration"
      :title="t('JRC_GLPI.reconcile')"
    >
      <p class="mb-3 text-sm text-n-slate-11">
        {{ t('JRC_GLPI.reconcile_help') }}
      </p>
      <form
        class="flex flex-wrap gap-3"
        @submit.prevent="reconcileCommand"
      >
        <input
          v-model="reconcile.command_id"
          required
          type="number"
          min="1"
          :placeholder="t('JRC_GLPI.command_number')"
          :aria-label="t('JRC_GLPI.command_number')"
          class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
        />
        <input
          v-model="reconcile.remote_id"
          required
          type="number"
          min="1"
          :placeholder="t('JRC_GLPI.id')"
          :aria-label="t('JRC_GLPI.id')"
          class="!mb-0 h-10 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 px-3 text-sm"
        />
        <Button
          type="submit"
          :label="t('JRC_GLPI.reconcile')"
          :disabled="busy"
        />
      </form>
      <p
        v-if="state.data.reconcile"
        class="mt-3 text-sm"
        role="status"
      >
        {{
          t('JRC_GLPI.commands.succeeded', {
            id: state.data.reconcile.command.remote_id,
          })
        }}
      </p>
    </Panel>
  </section>
</template>
