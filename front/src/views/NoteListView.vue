<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { RouterLink } from 'vue-router'
import { notesApi } from '../api/notes'
import type { Note } from '../types/api'

const notes = ref<Note[]>([])
const loading = ref(false)
const query = ref('')

async function load() {
  loading.value = true
  try {
    const res = query.value ? await notesApi.search(query.value) : await notesApi.list({ page: 1, page_size: 30 })
    notes.value = res.data.notes
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-5">
    <div class="flex items-center gap-3">
      <input
        v-model="query"
        class="h-10 flex-1 rounded-md border border-[var(--color-border)] bg-[var(--color-card)] px-3"
        placeholder="搜索笔记"
        @keydown.enter="load"
      />
      <button class="rounded-md border border-[var(--color-border)] px-4 py-2" @click="load">搜索</button>
      <RouterLink class="rounded-md bg-[var(--color-accent)] px-4 py-2 text-white" to="/notes/new">新建</RouterLink>
    </div>

    <div v-if="loading" class="text-sm text-[var(--color-text-secondary)]">加载中</div>
    <div v-else class="grid gap-3">
      <RouterLink
        v-for="note in notes"
        :key="note.id"
        :to="`/notes/${note.id}`"
        class="rounded-md border border-[var(--color-border)] bg-[var(--color-card)] p-4 hover:border-[var(--color-accent)]"
      >
        <div class="flex items-center justify-between gap-3">
          <h2 class="font-medium">{{ note.title }}</h2>
          <span class="text-xs text-[var(--color-text-tertiary)]">{{ note.category || '未分类' }}</span>
        </div>
        <p class="mt-2 line-clamp-2 text-sm text-[var(--color-text-secondary)]">{{ note.content }}</p>
        <div class="mt-3 flex flex-wrap gap-2">
          <span v-for="tag in note.tags || []" :key="tag" class="rounded bg-[var(--color-bg-secondary)] px-2 py-0.5 text-xs">{{ tag }}</span>
        </div>
      </RouterLink>
    </div>
  </div>
</template>
