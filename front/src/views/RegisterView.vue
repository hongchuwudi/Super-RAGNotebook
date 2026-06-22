<script setup lang="ts">
import { ref } from 'vue'
import { RouterLink, useRouter } from 'vue-router'
import { authApi } from '../api/auth'
import { useUserStore } from '../stores/useUserStore'

const username = ref('')
const email = ref('')
const password = ref('')
const error = ref('')
const router = useRouter()
const userStore = useUserStore()

async function submit() {
  error.value = ''
  try {
    const data = await authApi.register({
      username: username.value,
      email: email.value,
      password: password.value,
      confirm_password: password.value,
    })
    userStore.login(data.token, data.user)
    router.push('/notes')
  } catch (err) {
    error.value = err instanceof Error ? err.message : '注册失败'
  }
}
</script>

<template>
  <main class="flex min-h-screen items-center justify-center bg-[var(--color-bg)] px-4">
    <form class="w-full max-w-sm rounded-md border border-[var(--color-border)] bg-[var(--color-card)] p-6" @submit.prevent="submit">
      <h1 class="font-heading text-2xl font-semibold">创建账号</h1>
      <div class="mt-6 space-y-4">
        <input v-model="username" placeholder="用户名" class="w-full rounded-md border border-[var(--color-border)] bg-transparent px-3 py-2" />
        <input v-model="email" placeholder="邮箱" class="w-full rounded-md border border-[var(--color-border)] bg-transparent px-3 py-2" />
        <input v-model="password" type="password" placeholder="密码" class="w-full rounded-md border border-[var(--color-border)] bg-transparent px-3 py-2" />
      </div>
      <p v-if="error" class="mt-3 text-sm text-[var(--color-danger)]">{{ error }}</p>
      <button class="mt-6 w-full rounded-md bg-[var(--color-accent)] px-4 py-2 text-white">注册</button>
      <RouterLink class="mt-4 block text-center text-sm text-[var(--color-accent)]" to="/login">返回登录</RouterLink>
    </form>
  </main>
</template>
