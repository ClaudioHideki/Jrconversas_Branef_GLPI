<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDesk';
import Button from 'dashboard/components-next/button/Button.vue';
import Pagination from 'dashboard/components-next/pagination/PaginationFooter.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { decodeCollection, decodeTicket } from '../helpers/contracts';
const { t } = useI18n();
const session = useServiceDesk();
const items = ref([]);
const meta = ref(null);
const selected = ref(null);
const page = ref(1);
const error = ref(false);
const loading = ref(false);
let epoch = 0;
let controller;
const clear = () => {
  epoch += 1;
  controller?.abort();
  items.value = [];
  selected.value = null;
  meta.value = null;
};
onBeforeUnmount(clear);
const load = async row => {
  epoch += 1;
  const generation = epoch;
  controller?.abort();
  controller = new AbortController();
  loading.value = true;
  error.value = false;
  const account = session.accountId.value;
  const context = session.state.context;
  try {
    const query = { page: page.value, per_page: 20 };
    const payload = row
      ? await API.ticket(account, row.id, controller.signal)
      : await API.list(account, 'tickets', query, controller.signal);
    if (generation !== epoch) return;
    if (row) selected.value = decodeTicket(payload, context, row.id);
    else {
      const result = decodeCollection(payload, context, 'tickets', query);
      items.value = result.items;
      meta.value = result.meta;
    }
  } catch {
    if (generation === epoch) {
      error.value = true;
      items.value = [];
      selected.value = null;
    }
  } finally {
    if (generation === epoch) loading.value = false;
  }
};
watch(
  [session.accountId, session.userId, () => session.state.status],
  () => {
    clear();
    page.value = 1;
    if (session.state.status === 'ready') load();
  },
  { immediate: true }
);
</script>

<template>
  <section class="grid gap-4" data-testid="jrc-native-history">
    <h2 class="text-xl font-semibold">
      {{ t('JRC_GLPI.workspace.native_history') }}
    </h2>
    <p class="text-sm text-n-slate-11">
      {{ t('JRC_GLPI.workspace.native_history_help') }}
    </p>
    <p v-if="loading" role="status">{{ t('JRC_GLPI.loading') }}</p>
    <p v-if="error" role="alert">{{ t('JRC_GLPI.error') }}</p>
    <article
      v-if="selected"
      class="grid gap-3 rounded-xl border border-n-weak p-4"
    >
      <h3 class="font-semibold">
        {{ selected.number }} · {{ selected.title }}
      </h3>
      <p class="whitespace-pre-wrap break-words text-sm">
        {{ selected.description }}
      </p>
      <p class="text-sm">{{ selected.status?.name }}</p>
      <Button
        :label="t('JRC_SERVICE_DESK.COMMON.back')"
        variant="outline"
        @click="selected = null"
      />
    </article>
    <template v-else>
      <button
        v-for="row in items"
        :key="row.id"
        type="button"
        class="rounded-lg border border-n-weak p-3 text-left text-sm hover:bg-n-slate-2"
        @click="load(row)"
      >
        {{ row.number }} · {{ row.title }}
      </button>
      <p v-if="!loading && !error && !items.length">
        {{ t('JRC_GLPI.empty_history') }}
      </p>
      <Pagination
        v-if="meta?.total"
        :current-page="meta.page"
        :items-per-page="meta.per_page"
        :total-items="meta.total"
        @update:current-page="
          page = $event;
          load();
        "
      />
    </template>
  </section>
</template>
