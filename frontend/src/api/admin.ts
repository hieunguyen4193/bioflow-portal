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

export async function deleteUser(userId: string): Promise<void> {
  await api.delete(`/admin/users/${userId}`)
}

// ── Gene expression cache management ────────────────────────────────────────
export interface CacheEntry {
  assay: string
  slot: string
  size_bytes: number
}

export interface CacheDataset {
  project: string
  filename: string
  size_mb: number
  caches: CacheEntry[]
}

export interface AssaySlotLayout {
  n_cells: number
  n_features: number
  assays: string[]
  assay_slots: Record<string, string[]>
}

export type CacheStatus = 'ready' | 'building' | 'not_cached' | 'error'

export interface CacheStatusResult {
  status: CacheStatus
  error?: string
}

export async function listCacheDatasets(): Promise<CacheDataset[]> {
  const { data } = await api.get<CacheDataset[]>('/admin/cache/datasets')
  return data
}

export async function inspectDataset(project: string, filename: string): Promise<AssaySlotLayout> {
  const { data } = await api.post<AssaySlotLayout>('/admin/cache/inspect', { project, filename })
  return data
}

export async function buildCache(
  project: string, filename: string, assay: string, slot: string
): Promise<{ status: string; message: string }> {
  const { data } = await api.post('/admin/cache/build', { project, filename, assay, slot })
  return data
}

export async function getCacheStatus(
  project: string, filename: string, assay: string, slot: string
): Promise<CacheStatusResult> {
  const { data } = await api.get<CacheStatusResult>('/admin/cache/status', {
    params: { project, filename, assay, slot },
  })
  return data
}

export async function deleteCache(
  project: string, filename: string, assay?: string, slot?: string
): Promise<{ status: string; removed: number }> {
  const { data } = await api.delete('/admin/cache', { params: { project, filename, assay, slot } })
  return data
}

export async function deleteProjectCache(project: string): Promise<{ status: string; removed: number; files: number }> {
  const { data } = await api.delete('/admin/cache/project', { params: { project } })
  return data
}

export async function rebuildCache(
  project: string, filename: string, assay: string, slot: string
): Promise<{ status: string; message: string }> {
  const { data } = await api.post('/admin/cache/rebuild', { project, filename, assay, slot })
  return data
}

// ── Whole-project cache jobs ─────────────────────────────────────────────────
export interface CacheOptions {
  assays: string[]
  slots: string[]
}

export interface ProjectCacheJobItem {
  filename: string
  assay: string
  slot: string
  status: 'running' | 'done' | 'skipped' | 'error'
  message?: string
  error?: string
}

export interface ProjectCacheJob {
  job_id: string
  project: string
  assays: string[]
  slots: string[]
  total: number
  items: ProjectCacheJobItem[]
  current: ProjectCacheJobItem | null
  status: 'running' | 'done' | 'cancelled'
  created_at: string
  finished_at?: string
}

export async function getCacheOptions(): Promise<CacheOptions> {
  const { data } = await api.get<CacheOptions>('/admin/cache/options')
  return data
}

export async function buildProjectCache(project: string, assays: string[], slots: string[]): Promise<{ job_id: string; total: number }> {
  const { data } = await api.post('/admin/cache/build-project', { project, assays, slots })
  return data
}

export async function listProjectCacheJobs(): Promise<ProjectCacheJob[]> {
  const { data } = await api.get<ProjectCacheJob[]>('/admin/cache/build-project')
  return data
}

export async function getProjectCacheJob(jobId: string): Promise<ProjectCacheJob> {
  const { data } = await api.get<ProjectCacheJob>(`/admin/cache/build-project/${jobId}`)
  return data
}

export async function cancelProjectCacheJob(jobId: string): Promise<void> {
  await api.post(`/admin/cache/build-project/${jobId}/cancel`)
}
