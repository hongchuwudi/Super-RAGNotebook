<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { reviewApi } from '../api/review'
import type { ReviewItem } from '../types/api'

const reviews = ref<ReviewItem[]>([])
const loading = ref(false)

async function load() {
  loading.value = true
  try {
    const data = await reviewApi.today()
    reviews.value = data.reviews
  } finally {
    loading.value = false
  }
}

async function done(noteId: string) {
  await reviewApi.markDone(noteId)
  await load()
}

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <button class="rounded-md border border-[var(--color-border)] px-4 py-2" @click="load">刷新</button>
    <div v-if="loading" class="text-sm text-[var(--color-text-secondary)]">加载中</div>
    <article v-for="item in reviews" :key="item.review_id" class="rounded-md border border-[var(--color-border)] bg-[var(--color-card)] p-4">
      <div class="flex items-center justify-between">
        <h2 class="font-medium">{{ item.title }}</h2>
        <button class="rounded-md bg-[var(--color-success)] px-3 py-1.5 text-sm text-white" @click="done(item.note_id)">完成</button>
      </div>
      <p class="mt-2 text-sm text-[var(--color-text-secondary)]">{{ item.content_preview }}</p>
    </article>
  </div>
</template>
