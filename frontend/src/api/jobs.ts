import api from './client'

export interface Job {
  id: string
  pipeline: string
  status: 'queued' | 'running' | 'done' | 'failed'
  params: Record<string, unknown>
  input_files: string[]
  output_dir: string | null
  log: string | null
  created_at: string
  updated_at: string
}

export interface OutputFile { name: string; size: number }

export async function uploadFiles(files: File[]): Promise<{ batch_id: string; files: { filename: string }[] }> {
  const form = new FormData()
  files.forEach((f) => form.append('files', f))
  const { data } = await api.post('/files/upload', form, {
    headers: { 'Content-Type': 'multipart/form-data' },
  })
  return data
}

export async function submitJob(pipeline: string, batchId: string, params: Record<string, unknown>): Promise<Job> {
  const { data } = await api.post<Job>('/jobs/', { pipeline, params: { batch_id: batchId, ...params } })
  return data
}

export async function listJobs(): Promise<Job[]> {
  const { data } = await api.get<Job[]>('/jobs/')
  return data
}

export async function getJob(id: string): Promise<Job> {
  const { data } = await api.get<Job>(`/jobs/${id}`)
  return data
}

export async function listOutputFiles(id: string): Promise<OutputFile[]> {
  const { data } = await api.get<OutputFile[]>(`/jobs/${id}/files`)
  return data
}

export async function stopJob(id: string)   { await api.post(`/jobs/${id}/stop`) }
export async function pauseJob(id: string)  { await api.post(`/jobs/${id}/pause`) }
export async function resumeJob(id: string) { await api.post(`/jobs/${id}/resume`) }

export function downloadUrl(jobId: string, filePath: string) {
  const token = localStorage.getItem('token') ?? ''
  return `/api/jobs/${jobId}/download/${filePath}?token=${encodeURIComponent(token)}`
}

export async function listPipelines() {
  const { data } = await api.get('/pipelines/')
  return data
}

export interface PipelineParam {
  key: string
  label: string
  type: string
  default: unknown
  options?: string[]
}

export interface PipelineStep {
  key: string
  label: string
  run_key: string | null
  params: PipelineParam[]
}

export interface Pipeline {
  label: string
  steps: PipelineStep[]
}

export async function getPipeline(id: string): Promise<Pipeline | null> {
  try {
    const { data } = await api.get<Pipeline>(`/pipelines/${id}`)
    return data
  } catch {
    return null
  }
}

export async function getPipelineReadme(id: string): Promise<string> {
  try {
    const { data } = await api.get<string>(`/pipelines/${id}/readme`, {
      responseType: 'text',
    })
    return data
  } catch {
    return 'No description available.'
  }
}
