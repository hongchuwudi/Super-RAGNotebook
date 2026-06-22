<script setup lang="ts">
import { ref } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { authApi } from '../api/auth'
import { useUserStore } from '../stores/useUserStore'

const username = ref('admin')
const password = ref('admin1234')
const error = ref('')
const loading = ref(false)
const router = useRouter()
const userStore = useUserStore()

async function submit() {
  loading.value = true
  error.value = ''
  try {
    const data = await authApi.login(username.value, password.value)
    userStore.login(data.token, data.user)
    router.push('/notes')
  } catch (err) {
    error.value = err instanceof Error ? err.message : '登录失败'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <main class="flex min-h-screen items-center justify-center bg-[var(--color-bg)] px-4">
    <form class="w-full max-w-sm rounded-md border border-[var(--color-border)] bg-[var(--color-card)] p-6" @submit.prevent="submit">
      <h1 class="font-heading text-2xl font-semibold">云笺集</h1>
      <div class="mt-6 space-y-4">
        <label class="block text-sm">
          <span class="text-[var(--color-text-secondary)]">用户名</span>
          <input v-model="username" class="mt-1 w-full rounded-md border border-[var(--color-border)] bg-transparent px-3 py-2" />
        </label>
        <label class="block text-sm">
          <span class="text-[var(--color-text-secondary)]">密码</span>
          <input v-model="password" type="password" class="mt-1 w-full rounded-md border border-[var(--color-border)] bg-transparent px-3 py-2" />
        </label>
      </div>
      <p v-if="error" class="mt-3 text-sm text-[var(--color-danger)]">{{ error }}</p>
      <button class="mt-6 w-full rounded-md bg-[var(--color-accent)] px-4 py-2 text-white disabled:opacity-60" :disabled="loading">
        {{ loading ? '登录中' : '登录' }}
      </button>
      <RouterLink class="mt-4 block text-center text-sm text-[var(--color-accent)]" to="/register">注册账号</RouterLink>
    </form>
  </main>
</template>
