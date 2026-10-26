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
  pathway_cache?: PathwayCacheEntry[]
  preset_project?: string   // set only when the session was loaded from a preset
  preset_name?:    string
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
  methods?: ('ORA' | 'GSEA')[]                         // omitted/empty = all
  databases?: ('GO' | 'KEGG' | 'WP' | 'MSIGDB')[]      // omitted/empty = all
  msigdb_collections?: string[]                        // omitted/empty = all for the species
  gene_source?: string                                 // display-only label for the cached result
}): Promise<PathwayStartResponse> {
  const { data } = await api.post<PathwayStartResponse>('/explore/pathway', params)
  return data
}

export type PathwayResults = Record<string, Record<string, unknown>[]>

export interface PathwayCacheEntry {
  cache_key:          string
  created_at:         string
  source_label:       string
  gene_source:        string | null
  species:            'auto' | 'hsa' | 'mmu'
  pval_cutoff:        number
  methods:            ('ORA' | 'GSEA')[]
  databases:          ('GO' | 'KEGG' | 'WP' | 'MSIGDB')[]
  msigdb_collections: string[]
  n_genes:            number
  n_tables:           number   // result tables with at least one enriched term
}

// Same cached-or-task shape as startDGE: identical gene list + settings return the
// stored result straight away instead of re-running clusterProfiler.
export type PathwayStartResponse =
  | { cached: true; cache_key: string; created_at: string; results: PathwayResults }
  | { cached: false; task_id: string }

export async function listPathwayCache(session_id: string): Promise<PathwayCacheEntry[]> {
  const { data } = await api.get<PathwayCacheEntry[]>('/explore/pathway-cache', { params: { session_id } })
  return data
}

export async function loadPathwayCacheEntry(
  session_id: string, cache_key: string
): Promise<PathwayCacheEntry & { result: PathwayResults }> {
  const { data } = await api.get(`/explore/pathway-cache/${cache_key}`, { params: { session_id } })
  return data
}

export async function deletePathwayCacheEntry(session_id: string, cache_key: string): Promise<void> {
  await api.delete(`/explore/pathway-cache/${cache_key}`, { params: { session_id } })
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
  results?: PathwayResults
  cache_key?: string
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

export async function saveSubclusterAsPreset(
  session_id: string, cache_key: string, project: string, name: string
): Promise<{ project: string; filename: string }> {
  const { data } = await api.post(`/explore/subcluster-cache/${cache_key}/save-preset`, { session_id, project, name })
  return data
}

// Routed through the authenticated axios client (a bare <a href> would skip the
// Bearer token and 401/403 now that these endpoints require login) — fetch as a
// blob and trigger the download client-side instead.
export async function downloadSubclusterRds(session_id: string, cache_key: string): Promise<void> {
  const { data } = await api.get(`/explore/subcluster-cache/${cache_key}/download`, {
    params: { session_id },
    responseType: 'blob',
  })
  const url = URL.createObjectURL(data as Blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `subcluster_${cache_key}.rds`
  a.click()
  URL.revokeObjectURL(url)
}

// ── Re-clustering ─────────────────────────────────────────────────────────────
// Re-runs FindClusters at a new resolution on the object's existing SNN graph and
// returns the assignments as one new metadata column (values aligned to cells).
// With save_to_original the column is also written back into the preset .rds.
export interface ReclusterResult {
  column:        string
  graph:         string
  built_graph:   boolean   // true when the graph was rebuilt (reduction picked, or the object had none)
  reduction:     string | null   // the reduction a rebuilt graph came from
  resolution:    number
  n_clusters:    number
  cluster_sizes: Record<string, number>
  values:        string[]
  cells:         string[]
  saved:         boolean
}

export async function startRecluster(params: {
  session_id: string
  cluster_resolution: number
  algorithm: number
  reduction: string   // '' = reuse the stored SNN graph
  num_pcs: number
  column_name: string
  save_to_original: boolean
}): Promise<{ task_id: string }> {
  const { data } = await api.post('/explore/recluster/start', params)
  return data
}

export async function getReclusterStatus(task_id: string): Promise<
  { status: 'running'; log?: string }
  | (ReclusterResult & { status: 'done'; log?: string })
  | { status: 'error'; error: string; log?: string }
  | { status: 'cancelled'; log?: string }
> {
  const { data } = await api.get(`/explore/recluster/${task_id}`)
  return data
}

export async function cancelRecluster(task_id: string): Promise<void> {
  await api.post(`/explore/recluster/${task_id}/cancel`)
}

// Same reasoning as downloadSubclusterRds: fetch the rendered HTML report through
// the authenticated client rather than a bare <a href> to the backend path.
export async function fetchCellChatReport(task_id: string): Promise<Blob> {
  const { data } = await api.get(`/explore/cellchat/html/${task_id}`, { responseType: 'blob' })
  return data
}
