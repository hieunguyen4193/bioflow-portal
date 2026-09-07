import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import {
  listCacheDatasets, inspectDataset, buildCache, getCacheStatus, deleteCache,
  CacheDataset, AssaySlotLayout,
} from '../api/admin'

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`
  const units = ['KB', 'MB', 'GB']
  let v = n / 1024
  let i = 0
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024
    i++
  }
  return `${v.toFixed(1)} ${units[i]}`
}

function datasetKey(d: { project: string; filename: string }): string {
  return `${d.project}/${d.filename}`
}

function DatasetCacheRow({ dataset }: { dataset: CacheDataset }) {
  const qc = useQueryClient()
  const [expanded, setExpanded] = useState(false)
  const [layout, setLayout] = useState<AssaySlotLayout | null>(null)
  const [loadingLayout, setLoadingLayout] = useState(false)
  const [assay, setAssay] = useState('')
  const [slot, setSlot] = useState('')
  const [building, setBuilding] = useState<{ assay: string; slot: string } | null>(null)

  async function handleExpand() {
    const next = !expanded
    setExpanded(next)
    if (next && !layout) {
      setLoadingLayout(true)
      try {
        const data = await inspectDataset(dataset.project, dataset.filename)
        setLayout(data)
        const firstAssay = data.assays[0] ?? ''
        setAssay(firstAssay)
        setSlot(firstAssay ? (data.assay_slots[firstAssay]?.[0] ?? '') : '')
      } catch (err: any) {
        toast.error(err.response?.data?.detail || `Failed to read ${dataset.filename}`)
        setExpanded(false)
      } finally {
        setLoadingLayout(false)
      }
    }
  }

  async function pollUntilDone(a: string, s: string) {
    for (;;) {
      await new Promise((r) => setTimeout(r, 2000))
      try {
        const res = await getCacheStatus(dataset.project, dataset.filename, a, s)
        if (res.status === 'ready') {
          toast.success(`Cached ${a}/${s} for ${dataset.filename}`)
          break
        }
        if (res.status === 'error') {
          toast.error(`Caching ${a}/${s} failed: ${(res.error || 'unknown error').slice(0, 300)}`)
          break
        }
      } catch {
        break
      }
    }
    setBuilding(null)
    qc.invalidateQueries({ queryKey: ['admin-cache-datasets'] })
  }

  async function handleBuild() {
    if (!assay || !slot) return
    try {
      const res = await buildCache(dataset.project, dataset.filename, assay, slot)
      toast(res.message)
      if (res.status === 'started') {
        setBuilding({ assay, slot })
        pollUntilDone(assay, slot)
      } else {
        qc.invalidateQueries({ queryKey: ['admin-cache-datasets'] })
      }
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Failed to start cache build')
    }
  }

  async function handleDelete(a: string, s: string) {
    if (!confirm(`Delete cache for ${a}/${s}?`)) return
    try {
      await deleteCache(dataset.project, dataset.filename, a, s)
      toast.success(`Deleted cache for ${a}/${s}`)
      qc.invalidateQueries({ queryKey: ['admin-cache-datasets'] })
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Failed to delete cache')
    }
  }

  const slotsForAssay = layout?.assay_slots[assay] ?? []
  const alreadyCached = dataset.caches.some((c) => c.assay === assay && c.slot === slot)

  return (
    <div className="border-b border-slate-100 last:border-b-0">
      <button
        onClick={handleExpand}
        className="w-full flex items-center justify-between px-4 py-2.5 text-sm hover:bg-slate-50 transition-colors text-left"
      >
        <span className="flex items-center gap-2 min-w-0">
          <span className={`text-slate-400 transition-transform ${expanded ? 'rotate-90' : ''}`}>›</span>
          <span className="text-slate-700 truncate">{dataset.filename}</span>
          <span className="text-xs text-slate-400 shrink-0">{dataset.size_mb} MB</span>
        </span>
        <span className="flex items-center gap-1.5 shrink-0 ml-2">
          {dataset.caches.length === 0 ? (
            <span className="text-xs text-slate-400 italic">no cache</span>
          ) : (
            dataset.caches.map((c) => (
              <span
                key={`${c.assay}/${c.slot}`}
                className="text-xs bg-emerald-100 text-emerald-700 px-1.5 py-0.5 rounded"
                title={formatBytes(c.size_bytes)}
              >
                {c.assay}/{c.slot}
              </span>
            ))
          )}
        </span>
      </button>

      {expanded && (
        <div className="px-4 py-3 bg-slate-50/60 border-t border-slate-100 space-y-3">
          {loadingLayout && <p className="text-xs text-slate-400">Reading assay/slot layout…</p>}

          {layout && (
            <>
              <p className="text-xs text-slate-500">
                {layout.n_cells.toLocaleString()} cells · {layout.n_features.toLocaleString()} features
              </p>

              {dataset.caches.length > 0 && (
                <div className="flex flex-wrap gap-1.5">
                  {dataset.caches.map((c) => (
                    <span
                      key={`${c.assay}/${c.slot}`}
                      className="flex items-center gap-1 text-xs bg-white border border-slate-200 rounded px-2 py-1"
                    >
                      <span className="text-slate-600">{c.assay}/{c.slot}</span>
                      <span className="text-slate-400">{formatBytes(c.size_bytes)}</span>
                      <button
                        onClick={() => handleDelete(c.assay, c.slot)}
                        className="text-red-500 hover:text-red-700 ml-1"
                        title="Delete this cache"
                      >
                        ×
                      </button>
                    </span>
                  ))}
                </div>
              )}

              <div className="flex flex-wrap items-end gap-2">
                <div>
                  <label className="text-xs text-slate-500 block mb-1">Assay</label>
                  <select
                    value={assay}
                    onChange={(e) => {
                      const a = e.target.value
                      setAssay(a)
                      setSlot(layout.assay_slots[a]?.[0] ?? '')
                    }}
                    className="border border-slate-300 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
                  >
                    {layout.assays.map((a) => (
                      <option key={a} value={a}>{a}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-xs text-slate-500 block mb-1">Slot</label>
                  <select
                    value={slot}
                    onChange={(e) => setSlot(e.target.value)}
                    className="border border-slate-300 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
                  >
                    {slotsForAssay.map((s) => (
                      <option key={s} value={s}>{s}</option>
                    ))}
                  </select>
                </div>
                <button
                  onClick={handleBuild}
                  disabled={!assay || !slot || !!building || alreadyCached}
                  className="bg-indigo-600 hover:bg-indigo-700 text-white px-3 py-1.5 rounded-lg text-sm font-medium disabled:opacity-50"
                >
                  {building ? `Caching ${building.assay}/${building.slot}…` : alreadyCached ? 'Already cached' : 'Run cache'}
                </button>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  )
}

export default function CacheManagementPanel() {
  const { data: datasets = [], isLoading } = useQuery({
    queryKey: ['admin-cache-datasets'],
    queryFn: listCacheDatasets,
  })
  const [search, setSearch] = useState('')

  const filtered = useMemo(() => {
    if (!search) return datasets
    const q = search.toLowerCase()
    return datasets.filter((d) => datasetKey(d).toLowerCase().includes(q))
  }, [datasets, search])

  const byProject = useMemo(() => {
    const map = new Map<string, CacheDataset[]>()
    for (const d of filtered) {
      const list = map.get(d.project) ?? []
      list.push(d)
      map.set(d.project, list)
    }
    return map
  }, [filtered])

  const totalCached = datasets.reduce((n, d) => n + d.caches.length, 0)

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <p className="text-sm text-slate-500">
          Pre-warm the gene-expression cache for any preset dataset so it loads instantly for users.
        </p>
        <p className="text-sm text-slate-400">
          {datasets.length} dataset{datasets.length === 1 ? '' : 's'} · {totalCached} cached pair{totalCached === 1 ? '' : 's'}
        </p>
      </div>

      <input
        type="text"
        placeholder="Search by project or filename…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="border border-slate-300 rounded-lg px-3 py-1.5 text-sm w-64 mb-4 focus:outline-none focus:ring-2 focus:ring-indigo-400"
      />

      {isLoading && <p className="text-slate-500">Loading…</p>}

      {!isLoading && datasets.length === 0 && (
        <div className="text-center py-16 text-slate-400">No preset datasets found on disk yet.</div>
      )}

      {!isLoading && datasets.length > 0 && filtered.length === 0 && (
        <div className="text-center py-12 text-slate-400">No datasets match "{search}".</div>
      )}

      {byProject.size > 0 && (
        <div className="space-y-4">
          {[...byProject.entries()].map(([project, files]) => (
            <div key={project} className="bg-white rounded-xl shadow overflow-hidden">
              <div className="px-4 py-3 border-b bg-slate-50">
                <span className="font-medium text-sm text-slate-700">{project}</span>
              </div>
              <div>
                {files.map((d) => (
                  <DatasetCacheRow key={datasetKey(d)} dataset={d} />
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
