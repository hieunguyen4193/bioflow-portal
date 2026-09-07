import { useEffect, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import {
  listAdminProjects, getCacheOptions, buildProjectCache, listProjectCacheJobs,
  getProjectCacheJob, cancelProjectCacheJob, ProjectCacheJob,
} from '../api/admin'

function statusColor(status: string): string {
  switch (status) {
    case 'done':    return 'bg-emerald-100 text-emerald-700'
    case 'error':   return 'bg-red-100 text-red-700'
    case 'skipped': return 'bg-slate-100 text-slate-500'
    default:        return 'bg-amber-100 text-amber-700'
  }
}

function toggle(list: string[], setList: (v: string[]) => void, value: string) {
  setList(list.includes(value) ? list.filter((v) => v !== value) : [...list, value])
}

export default function ProjectCacheJobPanel() {
  const qc = useQueryClient()
  const { data: projects = [] } = useQuery({ queryKey: ['admin-projects'], queryFn: listAdminProjects })
  const { data: options } = useQuery({ queryKey: ['admin-cache-options'], queryFn: getCacheOptions })

  const [project, setProject] = useState('')
  const [assays, setAssays] = useState<string[]>([])
  const [slots, setSlots] = useState<string[]>([])
  const [job, setJob] = useState<ProjectCacheJob | null>(null)
  const [starting, setStarting] = useState(false)

  // Default the checkboxes to "everything" once the fixed assay/slot options load.
  useEffect(() => {
    if (options && assays.length === 0 && slots.length === 0) {
      setAssays(options.assays)
      setSlots(options.slots)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [options])

  // Re-discover an in-progress run on mount, so navigating away and back doesn't lose it.
  useEffect(() => {
    listProjectCacheJobs()
      .then((jobs) => {
        const running = jobs.find((j) => j.status === 'running')
        if (running) setJob(running)
      })
      .catch(() => {})
  }, [])

  useEffect(() => {
    if (!job || job.status !== 'running') return
    const id = setInterval(async () => {
      try {
        const updated = await getProjectCacheJob(job.job_id)
        setJob(updated)
        if (updated.status !== 'running') {
          qc.invalidateQueries({ queryKey: ['admin-cache-datasets'] })
          const errors = updated.items.filter((i) => i.status === 'error').length
          if (updated.status === 'cancelled') {
            toast(`Cache run for ${updated.project} cancelled`)
          } else if (errors > 0) {
            toast.error(`Cache run for ${updated.project} finished with ${errors} error(s)`)
          } else {
            toast.success(`Cache run for ${updated.project} finished`)
          }
        }
      } catch {
        // transient poll failure — try again next tick
      }
    }, 2500)
    return () => clearInterval(id)
  }, [job?.job_id, job?.status, qc])

  async function handleStart() {
    if (!project || assays.length === 0 || slots.length === 0) return
    setStarting(true)
    try {
      const res = await buildProjectCache(project, assays, slots)
      toast.success(`Queued ${res.total} cache job(s) for ${project}`)
      setJob(await getProjectCacheJob(res.job_id))
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Failed to start project cache run')
    } finally {
      setStarting(false)
    }
  }

  async function handleCancel() {
    if (!job) return
    try {
      await cancelProjectCacheJob(job.job_id)
      toast('Cancelling — the current file will finish, then the run stops')
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Failed to cancel')
    }
  }

  const done = job?.items.filter((i) => i.status !== 'running').length ?? 0
  const isRunning = job?.status === 'running'

  return (
    <div className="bg-white rounded-xl shadow p-4 mb-6">
      <h3 className="font-semibold text-slate-700 mb-1">Cache an entire project</h3>
      <p className="text-xs text-slate-500 mb-3">
        Runs the cache build for every dataset in a project, one file at a time — without opening
        each file first to check what it has. Just picks from the assays/slots below.
      </p>

      <div className="flex flex-wrap items-end gap-5 mb-3">
        <div>
          <label className="text-xs text-slate-500 block mb-1">Project</label>
          <select
            value={project}
            onChange={(e) => setProject(e.target.value)}
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          >
            <option value="" disabled>Select a project…</option>
            {projects.map((p) => (
              <option key={p} value={p}>{p}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="text-xs text-slate-500 block mb-1">Assay</label>
          <div className="flex gap-3">
            {(options?.assays ?? []).map((a) => (
              <label key={a} className="flex items-center gap-1.5 text-sm text-slate-600">
                <input type="checkbox" checked={assays.includes(a)} onChange={() => toggle(assays, setAssays, a)} />
                {a}
              </label>
            ))}
          </div>
        </div>

        <div>
          <label className="text-xs text-slate-500 block mb-1">Data slot</label>
          <div className="flex gap-3">
            {(options?.slots ?? []).map((s) => (
              <label key={s} className="flex items-center gap-1.5 text-sm text-slate-600">
                <input type="checkbox" checked={slots.includes(s)} onChange={() => toggle(slots, setSlots, s)} />
                {s}
              </label>
            ))}
          </div>
        </div>

        <button
          onClick={handleStart}
          disabled={!project || assays.length === 0 || slots.length === 0 || starting || isRunning}
          className="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-lg text-sm font-medium disabled:opacity-50"
        >
          {starting ? 'Starting…' : isRunning ? 'A run is already in progress…' : 'Run cache for project'}
        </button>
      </div>

      {job && (
        <div className="border-t border-slate-100 pt-3 mt-1">
          <div className="flex items-center justify-between mb-2 gap-3">
            <p className="text-sm text-slate-700 min-w-0">
              <span className="font-medium">{job.project}</span>: {done}/{job.total} processed
              {job.current && (
                <span className="text-slate-400">
                  {' '}· now caching {job.current.filename} ({job.current.assay}/{job.current.slot})
                </span>
              )}
            </p>
            {isRunning && (
              <button
                onClick={handleCancel}
                className="text-xs border border-red-300 text-red-600 hover:bg-red-50 px-2 py-0.5 rounded transition-colors shrink-0"
              >
                Cancel
              </button>
            )}
          </div>
          <div className="w-full bg-slate-100 rounded-full h-1.5 mb-3">
            <div
              className="bg-indigo-500 h-1.5 rounded-full transition-all"
              style={{ width: `${job.total ? (done / job.total) * 100 : 0}%` }}
            />
          </div>
          {job.items.length > 0 && (
            <div className="max-h-48 overflow-y-auto space-y-1">
              {[...job.items].reverse().map((it, i) => (
                <div key={i} className="flex items-center justify-between text-xs px-2 py-1 rounded bg-slate-50">
                  <span className="text-slate-600 truncate" title={it.error}>
                    {it.filename} — {it.assay}/{it.slot}
                  </span>
                  <span className={`px-1.5 py-0.5 rounded shrink-0 ml-2 ${statusColor(it.status)}`} title={it.error}>
                    {it.status}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
