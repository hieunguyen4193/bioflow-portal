import api from './client'

export interface SeuratMeta {
  session_id: string
  n_cells:    number
  n_features: number
  assays:     string[]
  reductions: Record<string, { x: number[]; y: number[]; cells: string[] }>
  metadata:   Record<string, string[]>
  cells:      string[]
  genes:      string[]
}

export interface PresetFile {
  name: string
  filename: string
  size_mb: number
}

export interface PresetProject {
  project: string
  files: PresetFile[]
}

export async function listPresets(): Promise<PresetProject[]> {
  const { data } = await api.get<PresetProject[]>('/explore/presets')
  return data
}

export async function loadPreset(project: string, filename: string): Promise<SeuratMeta> {
  const { data } = await api.post<SeuratMeta>('/explore/presets/load', { project, filename }, { timeout: 180000 })
  return data
}

export async function uploadRds(file: File): Promise<SeuratMeta> {
  const form = new FormData()
  form.append('file', file)
  const { data } = await api.post<SeuratMeta>('/explore/upload', form, {
    headers: { 'Content-Type': 'multipart/form-data' },
    timeout: 180000,
  })
  return data
}

export async function getGeneExpression(
  session_id: string, genes: string, assay: string, slot: string
): Promise<{ cells: string[]; expression: Record<string, number[]> }> {
  const { data } = await api.post('/explore/gene', { session_id, genes, assay, slot })
  return data
}

export interface DGEResult {
  markers:      Record<string, unknown>[]
  excluded_tcr: string[]
  excluded_bcr: string[]
  species:      string
}

export async function runDGE(params: {
  session_id: string
  mode: 'clusters' | 'conditions'
  group_by: string
  assay: string
  slot: string
  test_use: string
  ident1?: string
  ident2?: string
  rm_tcr: boolean
  rm_bcr: boolean
}): Promise<DGEResult> {
  const { data } = await api.post<DGEResult>('/explore/dge', params, { timeout: 600000 })
  return data
}
