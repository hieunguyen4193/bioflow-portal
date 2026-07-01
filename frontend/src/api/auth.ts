import api from './client'

export interface User { id: string; username: string; email: string | null; full_name: string; is_admin: boolean }

export async function login(username: string, password: string): Promise<string> {
  const form = new FormData()
  form.append('username', username)
  form.append('password', password)
  const { data } = await api.post<{ access_token: string }>('/auth/login', form)
  return data.access_token
}

export async function register(username: string, full_name: string, password: string, email?: string) {
  const { data } = await api.post('/auth/register', { username, full_name, password, email: email || undefined })
  return data
}

export async function getMe(): Promise<User> {
  const { data } = await api.get<User>('/auth/me')
  return data
}
