import { create } from 'zustand'
import { User } from '../api/auth'

interface AuthState {
  token: string | null
  user: User | null
  setToken: (t: string) => void
  setUser: (u: User) => void
  logout: () => void
}

export const useAuthStore = create<AuthState>((set) => ({
  token: localStorage.getItem('token'),
  user: null,
  setToken: (token) => { localStorage.setItem('token', token); set({ token }) },
  setUser: (user) => set({ user }),
  logout: () => { localStorage.removeItem('token'); set({ token: null, user: null }) },
}))
