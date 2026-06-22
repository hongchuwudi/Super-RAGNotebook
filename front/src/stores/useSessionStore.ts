import { defineStore } from 'pinia'
import type { ChatSession } from '../types/api'

export const useSessionStore = defineStore('sessions', {
  state: () => ({
    sessions: [] as ChatSession[],
    currentSession: null as ChatSession | null,
    loading: false,
  }),
  actions: {
    setSessions(sessions: ChatSession[]) {
      this.sessions = sessions
    },
    setCurrentSession(session: ChatSession | null) {
      this.currentSession = session
    },
    addSession(session: ChatSession) {
      this.sessions = [session, ...this.sessions]
    },
    removeSession(id: string) {
      this.sessions = this.sessions.filter((session) => session.id !== id)
      if (this.currentSession?.id === id) this.currentSession = null
    },
    setLoading(loading: boolean) {
      this.loading = loading
    },
    clearSessions() {
      this.sessions = []
      this.currentSession = null
    },
  },
})
