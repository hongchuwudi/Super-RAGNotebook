<script setup lang="ts">
import { ref } from 'vue'
import { chatApi } from '../api/chat'

const query = ref('')
const messages = ref<{ role: 'user' | 'assistant'; content: string }[]>([])
const loading = ref(false)

async function send() {
  if (!query.value.trim()) return
  const current = query.value
  query.value = ''
  messages.value.push({ role: 'user', content: current })
  messages.value.push({ role: 'assistant', content: '' })
  loading.value = true
  try {
    const response = await chatApi.queryStream({ query: current })
    const reader = response.body?.getReader()
    const decoder = new TextDecoder()
    if (!reader) return
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      const chunk = decoder.decode(value)
      for (const line of chunk.split('\n')) {
        if (!line.startsWith('data:')) continue
        const raw = line.slice(5).trim()
        if (!raw || raw === '[DONE]') continue
        try {
          const data = JSON.parse(raw)
          if (data.type === 'response' && data.content) {
            messages.value[messages.value.length - 1].content += data.content
          }
        } catch {
          messages.value[messages.value.length - 1].content += raw
        }
      }
    }
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="flex h-[calc(100vh-8rem)] flex-col rounded-md border border-[var(--color-border)] bg-[var(--color-card)]">
    <div class="flex-1 space-y-4 overflow-auto p-5">
      <div v-for="(message, index) in messages" :key="index" class="max-w-3xl rounded-md p-3" :class="message.role === 'user' ? 'ml-auto bg-[var(--color-accent-bg)]' : 'bg-[var(--color-bg-secondary)]'">
        <p class="whitespace-pre-wrap text-sm">{{ message.content }}</p>
      </div>
    </div>
    <form class="flex gap-3 border-t border-[var(--color-border)] p-4" @submit.prevent="send">
      <input v-model="query" class="h-11 flex-1 rounded-md border border-[var(--color-border)] bg-transparent px-3" placeholder="输入问题" />
      <button class="rounded-md bg-[var(--color-accent)] px-5 text-white disabled:opacity-60" :disabled="loading">发送</button>
    </form>
  </div>
</template>
