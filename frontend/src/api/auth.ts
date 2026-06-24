import api from './client'

export interface User { id: string; email: string; full_name: string; is_admin: boolean }

export async function login(email: string, password: string): Promise<string> {
  const form = new FormData()
  form.append('username', email)
  form.append('password', password)
  const { data } = await api.post<{ access_token: string }>('/auth/login', form)
  return data.access_token
}

export async function register(email: string, full_name: string, password: string) {
  const { data } = await api.post('/auth/register', { email, full_name, password })
  return data
}

export async function getMe(): Promise<User> {
  const { data } = await api.get<User>('/auth/me')
  return data
}
