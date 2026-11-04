<script setup>
import { onBeforeUnmount, onMounted, ref, watch } from 'vue';
import {
  fullSchema,
  buildEditor,
  EditorState,
  EditorView,
} from '@chatwoot/prosemirror-schema';
import { DOMParser, DOMSerializer, Schema } from 'prosemirror-model';
import DOMPurify from 'dompurify';
const props = defineProps({
  modelValue: { type: String, default: '' },
  label: { type: String, required: true },
  disabled: Boolean,
  required: Boolean,
});
const emit = defineEmits(['update:modelValue']);
const host = ref(null);
// Remote media is delivered only by the authenticated document flow.
const schema = new Schema({
  nodes: fullSchema.spec.nodes.update('image', {
    ...fullSchema.spec.nodes.get('image'),
    parseDOM: [],
    toDOM: () => ['span'],
  }),
  marks: fullSchema.spec.marks,
});
let view;
const parse = value => {
  const element = document.createElement('div');
  element.innerHTML = DOMPurify.sanitize(value, {
    FORBID_TAGS: [
      'img',
      'iframe',
      'video',
      'audio',
      'object',
      'embed',
      'style',
    ],
  });
  return DOMParser.fromSchema(schema).parse(element);
};
const serialize = doc => {
  const element = document.createElement('div');
  element.appendChild(
    DOMSerializer.fromSchema(schema).serializeFragment(doc.content)
  );
  return element.innerHTML;
};
onMounted(() => {
  view = new EditorView(host.value, {
    state: EditorState.create({
      doc: parse(props.modelValue),
      plugins: buildEditor({
        schema,
        enabledMenuOptions: [
          'strong',
          'em',
          'link',
          'bulletList',
          'orderedList',
          'undo',
          'redo',
          'table',
        ],
      }),
    }),
    editable: () => !props.disabled,
    attributes: {
      role: 'textbox',
      'aria-label': props.label,
      'aria-multiline': 'true',
      'aria-required': String(props.required),
    },
    dispatchTransaction(transaction) {
      view.updateState(view.state.apply(transaction));
      if (transaction.docChanged)
        emit('update:modelValue', serialize(view.state.doc));
    },
  });
});
watch(
  () => props.disabled,
  () => view?.setProps({ editable: () => !props.disabled })
);
watch(
  () => props.required,
  value => view?.dom.setAttribute('aria-required', String(value))
);
watch(
  () => props.modelValue,
  value => {
    if (!view || serialize(view.state.doc) === value) return;
    view.updateState(
      EditorState.create({ doc: parse(value), plugins: view.state.plugins })
    );
  }
);
onBeforeUnmount(() => view?.destroy());
</script>

<template>
  <div
    ref="host"
    class="prose prose-sm max-w-none overflow-x-auto rounded-lg border border-n-weak bg-n-solid-1 p-3 text-n-slate-12"
    data-testid="glpi-rich-editor"
  />
</template>
