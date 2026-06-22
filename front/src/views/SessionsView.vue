<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useUserStore } from '../stores/useUserStore'
import client from '../api/client'
import { endpoints } from '../api/endpoints'

const sessions = ref<string[]>([])
const userStore = useUserStore()

async function load() {
  const userId = userStore.userInfo?.id || userStore.userInfo?.uuid || userStore.userInfo?.user_id
  if (!userId) return
  const res = await client.get<{ data: { sessions: string[] } }>(endpoints.getUserSessions(userId))
  sessions.value = res.data.data.sessions
}

onMounted(load)
</script>

<template>
  <div class="space-y-3">
    <button class="rounded-md border border-[var(--color-border)] px-4 py-2" @click="load">刷新</button>
    <RouterLink v-for="id in sessions" :key="id" :to="`/chat/${id}`" class="block rounded-md border border-[var(--color-border)] bg-[var(--color-card)] p-4">
      {{ id }}
    </RouterLink>
  </div>
</template>
