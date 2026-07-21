import api from './client'
import { User } from './auth'

export interface ProjectAccessGrant {
  id: string
  user_id: string
  username: string
  project_name: string
}

export async function listAdminUsers(): Promise<User[]> {
  const { data } = await api.get<User[]>('/admin/users')
  return data
}

export async function listAdminProjects(): Promise<string[]> {
  const { data } = await api.get<string[]>('/admin/projects')
  return data
}

export async function listProjectAccess(): Promise<ProjectAccessGrant[]> {
  const { data } = await api.get<ProjectAccessGrant[]>('/admin/project-access')
  return data
}

export async function grantProjectAccess(username: string, project_name: string): Promise<ProjectAccessGrant> {
  const { data } = await api.post<ProjectAccessGrant>('/admin/project-access', { username, project_name })
  return data
}

export async function revokeProjectAccess(grantId: string): Promise<void> {
  await api.delete(`/admin/project-access/${grantId}`)
}
