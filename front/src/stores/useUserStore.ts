import { defineStore } from 'pinia'
import type { UserInfo } from '../types/api'

const storedUser = localStorage.getItem('user_info')

export const useUserStore = defineStore('user', {
  state: () => ({
    userInfo: storedUser ? (JSON.parse(storedUser) as UserInfo) : null,
    token: localStorage.getItem('jwt_token') || '',
    userBio: '',
  }),
  getters: {
    isLogin: (state) => Boolean(state.token),
  },
  actions: {
    login(token: string, user: UserInfo) {
      localStorage.setItem('jwt_token', token)
      localStorage.setItem('user_info', JSON.stringify(user))
      this.token = token
      this.userInfo = user
    },
    logout() {
      localStorage.removeItem('jwt_token')
      localStorage.removeItem('user_info')
      this.token = ''
      this.userInfo = null
      this.userBio = ''
    },
    setUserInfo(info: UserInfo) {
      localStorage.setItem('user_info', JSON.stringify(info))
      this.userInfo = info
    },
    setToken(token: string) {
      localStorage.setItem('jwt_token', token)
      this.token = token
    },
    setUserBio(bio: string) {
      this.userBio = bio
    },
  },
})
