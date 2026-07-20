import api from './client'

export interface SeuratMeta {
  session_id:  string
  n_cells:     number
  n_features:  number
  assays:      string[]
  assay_slots: Record<string, string[]>
  reductions:  Record<string, { x: number[]; y: number[]; cells: string[] }>
  metadata:    Record<string, string[]>
  cells:       string[]
  genes:       string[]
  dge_cache?:  DgeCacheEntry[]
  subcluster_cache?: SubclusterCacheEntry[]
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
  cache_key?:   string
  cached?:      boolean
}

export interface DgeCacheEntry {
  cache_key:      string
  created_at:     string
  source_label:   string
  mode:           'clusters' | 'conditions'
  group_by:       string
  assay:          string
  slot:           string
  test_use:       string
  ident1:         string | null
  ident2:         string | null
  rm_tcr:         boolean
  rm_bcr:         boolean
  min_pct:        number
  pval_cutoff:    number
  logfc_cutoff:   number
  species:        string
  n_markers:      number
  n_significant:  number
}

// DGE runs in the background so it can be cancelled mid-run (a DESeq2 run can take
// many minutes) — startDGE returns immediately: either the cached result (cached:
// true, no task_id, same shape as before) or a task_id to poll/cancel (cached: false).
export type DGEStartResponse = (DGEResult & { cached: true }) | { cached: false; task_id: string }

export async function startDGE(params: {
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
  min_pct: number
  pval_cutoff: number
  logfc_cutoff: number
}): Promise<DGEStartResponse> {
  const { data } = await api.post<DGEStartResponse>('/explore/dge/start', params)
  return data
}

export async function getDgeStatus(task_id: string): Promise<
  { status: 'running'; log?: string }
  | (DGEResult & { status: 'done'; log?: string })
  | { status: 'error'; error: string; log?: string }
  | { status: 'cancelled'; log?: string }
> {
  const { data } = await api.get(`/explore/dge/${task_id}`)
  return data
}

export async function cancelDGE(task_id: string): Promise<void> {
  await api.post(`/explore/dge/${task_id}/cancel`)
}

export async function listDgeCache(session_id: string): Promise<DgeCacheEntry[]> {
  const { data } = await api.get<DgeCacheEntry[]>('/explore/dge-cache', { params: { session_id } })
  return data
}

export async function loadDgeCacheEntry(
  session_id: string, cache_key: string
): Promise<DgeCacheEntry & { result: DGEResult }> {
  const { data } = await api.get(`/explore/dge-cache/${cache_key}`, { params: { session_id } })
  return data
}

export async function deleteDgeCacheEntry(session_id: string, cache_key: string): Promise<void> {
  await api.delete(`/explore/dge-cache/${cache_key}`, { params: { session_id } })
}

export async function startPathwayAnalysis(params: {
  session_id: string
  csv_data: string   // JSON-stringified array of marker rows
  species?: 'hsa' | 'mmu' | 'auto'
  pval_cutoff: number
}): Promise<{ task_id: string }> {
  const { data } = await api.post('/explore/pathway', params)
  return data
}

export async function startCellChat(params: {
  session_id: string
  sample_id?: string
  filter10cells?: string
  reduction_name?: string
  cluster_name?: string
  input_spec?: string
}): Promise<{ task_id: string }> {
  const { data } = await api.post('/explore/cellchat', params)
  return data
}

export async function getCellChatStatus(task_id: string): Promise<{
  status: 'running' | 'done' | 'error'
  log?: string
  report_url?: string
  error?: string
}> {
  const { data } = await api.get(`/explore/cellchat/${task_id}`)
  return data
}

export async function cancelPathwayAnalysis(task_id: string): Promise<void> {
  await api.post(`/explore/pathway/${task_id}/cancel`)
}

export async function cancelCellChat(task_id: string): Promise<void> {
  await api.post(`/explore/cellchat/${task_id}/cancel`)
}

export async function getCacheStatus(
  session_id: string, assay?: string, slot?: string
): Promise<{ status: 'building' | 'ready' | 'not_cached' }> {
  const { data } = await api.get('/explore/cache-status', {
    params: { session_id, ...(assay ? { assay } : {}), ...(slot ? { slot } : {}) },
  })
  return data
}

export async function startCacheBuild(
  session_id: string, assay: string, slot: string
): Promise<{ status: 'exists' | 'building' | 'started'; message: string }> {
  const { data } = await api.post('/explore/cache-build', { session_id, assay, slot })
  return data
}

export interface ExprCacheEntry {
  assay:      string
  slot:       string
  size_bytes: number
}

export async function listExprCache(session_id: string): Promise<ExprCacheEntry[]> {
  const { data } = await api.get<ExprCacheEntry[]>('/explore/cache-list', { params: { session_id } })
  return data
}

// Omit assay/slot to delete every cached (assay, slot) pair for this session.
export async function deleteExprCache(
  session_id: string, assay?: string, slot?: string
): Promise<{ status: string; removed: number }> {
  const { data } = await api.delete('/explore/cache', {
    params: { session_id, ...(assay ? { assay } : {}), ...(slot ? { slot } : {}) },
  })
  return data
}

export async function getPathwayResult(task_id: string): Promise<{
  status: 'running' | 'done' | 'error'
  log?: string
  results?: Record<string, Record<string, unknown>[]>
  error?: string
}> {
  const { data } = await api.get(`/explore/pathway/${task_id}`)
  return data
}

// ── Gene module score ─────────────────────────────────────────────────────────
// Runs AddModuleScore in the pipeline image (same background-task shape as
// pathway analysis) and returns {cells, expression} — one array of per-cell
// scores per module, exactly like getGeneExpression's per-gene shape — so the
// UMAP/violin plotting code that already exists for genes can be reused as-is.
export async function startModuleScore(params: {
  session_id: string
  assay: string
  ctrl: number
  file: File
}): Promise<{ task_id: string }> {
  const form = new FormData()
  form.append('session_id', params.session_id)
  form.append('assay', params.assay)
  form.append('ctrl', String(params.ctrl))
  form.append('file', params.file)
  const { data } = await api.post('/explore/module-score/start', form, {
    headers: { 'Content-Type': 'multipart/form-data' },
  })
  return data
}

export async function getModuleScoreStatus(task_id: string): Promise<
  { status: 'running'; log?: string }
  | { status: 'done'; log?: string; cells: string[]; expression: Record<string, number[]> }
  | { status: 'error'; error: string; log?: string }
  | { status: 'cancelled'; log?: string }
> {
  const { data } = await api.get(`/explore/module-score/${task_id}`)
  return data
}

export async function cancelModuleScore(task_id: string): Promise<void> {
  await api.post(`/explore/module-score/${task_id}/cancel`)
}

// ── Sub-clustering ────────────────────────────────────────────────────────────
export interface SubclusterResult {
  n_cells_before: number
  n_cells_after:  number
  species:        string
  excluded_tcr:   string[]
  excluded_bcr:   string[]
  reductions:     Record<string, { x: number[]; y: number[]; cells: string[] }>
  metadata:       Record<string, string[]>
  cells:          string[]
  cache_key?:     string
  cached?:        boolean
}

export interface SubclusterCacheEntry {
  cache_key:          string
  created_at:         string
  source_label:       string
  group_by:           string
  clusters:           string[]
  use_sctransform:    boolean
  vars_to_regress:    string
  num_pca:            number
  num_pcs_umap:       number
  num_pcs_cluster:    number
  cluster_resolution: number
  rm_tcr:             boolean
  rm_bcr:             boolean
  species:            string
  n_cells_before:     number
  n_cells_after:      number
}

// Sub-clustering re-runs SCTransform/PCA/UMAP/clustering on the subset, which can
// take minutes — same cancellable background-task shape as startDGE.
export type SubclusterStartResponse = (SubclusterResult & { cached: true }) | { cached: false; task_id: string }

export async function startSubcluster(params: {
  session_id: string
  group_by: string
  clusters: string
  use_sctransform: boolean
  vars_to_regress: string
  num_pca: number
  num_pcs_umap: number
  num_pcs_cluster: number
  cluster_resolution: number
  rm_tcr: boolean
  rm_bcr: boolean
}): Promise<SubclusterStartResponse> {
  const { data } = await api.post<SubclusterStartResponse>('/explore/subcluster/start', params)
  return data
}

export async function getSubclusterStatus(task_id: string): Promise<
  { status: 'running'; log?: string }
  | (SubclusterResult & { status: 'done'; log?: string })
  | { status: 'error'; error: string; log?: string }
  | { status: 'cancelled'; log?: string }
> {
  const { data } = await api.get(`/explore/subcluster/${task_id}`)
  return data
}

export async function cancelSubcluster(task_id: string): Promise<void> {
  await api.post(`/explore/subcluster/${task_id}/cancel`)
}

export async function listSubclusterCache(session_id: string): Promise<SubclusterCacheEntry[]> {
  const { data } = await api.get<SubclusterCacheEntry[]>('/explore/subcluster-cache', { params: { session_id } })
  return data
}

export async function loadSubclusterCacheEntry(
  session_id: string, cache_key: string
): Promise<SubclusterCacheEntry & { result: SubclusterResult }> {
  const { data } = await api.get(`/explore/subcluster-cache/${cache_key}`, { params: { session_id } })
  return data
}

export async function deleteSubclusterCacheEntry(session_id: string, cache_key: string): Promise<void> {
  await api.delete(`/explore/subcluster-cache/${cache_key}`, { params: { session_id } })
}

// Direct <a href> download link (not routed through the axios client) — mirrors
// the CellChat HTML report link, which the backend also serves outside /api.
export function subclusterDownloadUrl(session_id: string, cache_key: string): string {
  return `/explore/subcluster-cache/${cache_key}/download?session_id=${encodeURIComponent(session_id)}`
}
