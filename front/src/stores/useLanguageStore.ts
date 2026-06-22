import { defineStore } from 'pinia'

type Lang = 'zh-CN' | 'en-US'

export const useLanguageStore = defineStore('language', {
  state: () => ({
    lang: ((localStorage.getItem('language') as Lang) || 'zh-CN') as Lang,
  }),
  actions: {
    setLang(lang: Lang) {
      this.lang = lang
      localStorage.setItem('language', lang)
    },
  },
})
