<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { knowledgeApi } from '../api/knowledge'
import type { KnowledgeDocument } from '../types/api'

const documents = ref<KnowledgeDocument[]>([])
const loading = ref(false)

async function load() {
  loading.value = true
  try {
    const res = await knowledgeApi.list()
    documents.value = res.data.documents
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-5">
    <div class="flex items-center justify-between">
      <h2 class="font-heading text-lg font-semibold">知识库文档</h2>
      <button class="rounded-md border border-[var(--color-border)] px-4 py-2" @click="load">刷新</button>
    </div>
    <div v-if="loading" class="text-sm text-[var(--color-text-secondary)]">加载中</div>
    <div v-else class="grid gap-3">
      <article v-for="doc in documents" :key="doc.id" class="rounded-md border border-[var(--color-border)] bg-[var(--color-card)] p-4">
        <div class="flex items-center justify-between">
          <h3 class="font-medium">{{ doc.original_filename || doc.filename }}</h3>
          <span class="text-xs text-[var(--color-text-secondary)]">{{ doc.chunk_count }} chunks</span>
        </div>
        <p class="mt-2 text-sm text-[var(--color-text-secondary)]">{{ doc.preview }}</p>
      </article>
    </div>
  </div>
</template>
