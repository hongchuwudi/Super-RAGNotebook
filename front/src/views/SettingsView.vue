<script setup lang="ts">
import { useThemeStore } from '../stores/useThemeStore'
import { useLanguageStore } from '../stores/useLanguageStore'

const themeStore = useThemeStore()
const languageStore = useLanguageStore()
</script>

<template>
  <div class="max-w-xl space-y-4 rounded-md border border-[var(--color-border)] bg-[var(--color-card)] p-5">
    <label class="flex items-center justify-between">
      <span>深色模式</span>
      <input type="checkbox" :checked="themeStore.theme === 'dark'" @change="themeStore.toggleTheme()" />
    </label>
    <label class="block">
      <span class="text-sm text-[var(--color-text-secondary)]">语言</span>
      <select v-model="languageStore.lang" class="mt-1 w-full rounded-md border border-[var(--color-border)] bg-transparent px-3 py-2" @change="languageStore.setLang(languageStore.lang)">
        <option value="zh-CN">中文</option>
        <option value="en-US">English</option>
      </select>
    </label>
  </div>
</template>
