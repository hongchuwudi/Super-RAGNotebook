<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { authApi } from '../api/auth'
import { useUserStore } from '../stores/useUserStore'
import type { UserInfo } from '../types/api'

const userStore = useUserStore()
const profile = ref<UserInfo | null>(userStore.userInfo)

async function load() {
  const res = await authApi.getProfile()
  profile.value = res.data
  userStore.setUserInfo(res.data)
}

onMounted(load)
</script>

<template>
  <div class="max-w-xl rounded-md border border-[var(--color-border)] bg-[var(--color-card)] p-5">
    <h2 class="font-heading text-lg font-semibold">账号资料</h2>
    <dl v-if="profile" class="mt-4 space-y-3 text-sm">
      <div class="flex justify-between"><dt>用户名</dt><dd>{{ profile.username }}</dd></div>
      <div class="flex justify-between"><dt>邮箱</dt><dd>{{ profile.email }}</dd></div>
      <div class="flex justify-between"><dt>状态</dt><dd>{{ profile.is_active ? '启用' : '未启用' }}</dd></div>
    </dl>
  </div>
</template>
