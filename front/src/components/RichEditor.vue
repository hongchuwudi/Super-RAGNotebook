<script setup lang="ts">
import { watch } from 'vue'
import StarterKit from '@tiptap/starter-kit'
import { EditorContent, useEditor } from '@tiptap/vue-3'

const props = defineProps<{ modelValue: string }>()
const emit = defineEmits<{ 'update:modelValue': [value: string] }>()

const editor = useEditor({
  content: props.modelValue,
  extensions: [StarterKit],
  editorProps: {
    attributes: {
      class: 'min-h-[420px] rounded-md border border-[var(--color-border)] bg-[var(--color-card)] px-5 py-4 outline-none',
    },
  },
  onUpdate: ({ editor }) => emit('update:modelValue', editor.getText() ? editor.getHTML() : ''),
})

watch(
  () => props.modelValue,
  (value) => {
    if (editor.value && editor.value.getHTML() !== value) {
      editor.value.commands.setContent(value || '', false)
    }
  }
)
</script>

<template>
  <EditorContent :editor="editor" />
</template>
