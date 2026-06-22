<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import RichEditor from '../components/RichEditor.vue'
import { notesApi } from '../api/notes'

const route = useRoute()
const router = useRouter()
const noteId = route.params.id as string | undefined
const isNew = !noteId
const title = ref('')
const content = ref('')
const category = ref('')
const saving = ref(false)
const message = ref('')

async function load() {
  if (!noteId) return
  const res = await notesApi.get(noteId)
  title.value = res.data.title
  content.value = res.data.content
  category.value = res.data.category || ''
}

async function save() {
  saving.value = true
  message.value = ''
  try {
    if (isNew) {
      const res = await notesApi.create({ title: title.value || '未命名笔记', content: content.value, category: category.value })
      router.replace(`/notes/${res.data.id}`)
    } else if (noteId) {
      await notesApi.update(noteId, { title: title.value, content: content.value, category: category.value })
      message.value = '已保存'
    }
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="mx-auto max-w-5xl space-y-4">
    <div class="flex items-center gap-3">
      <input v-model="title" class="h-11 flex-1 bg-transparent font-heading text-2xl font-semibold outline-none" placeholder="未命名笔记" />
      <input v-model="category" class="h-10 w-36 rounded-md border border-[var(--color-border)] bg-[var(--color-card)] px-3" placeholder="分类" />
      <button class="rounded-md bg-[var(--color-accent)] px-4 py-2 text-white disabled:opacity-60" :disabled="saving" @click="save">
        {{ saving ? '保存中' : '保存' }}
      </button>
    </div>
    <p v-if="message" class="text-sm text-[var(--color-success)]">{{ message }}</p>
    <RichEditor v-model="content" />
  </div>
</template>
