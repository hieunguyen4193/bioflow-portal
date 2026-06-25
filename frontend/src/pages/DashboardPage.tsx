import { useState, useMemo } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { listJobs, stopJob, pauseJob, resumeJob, Job } from '../api/jobs'
import toast from 'react-hot-toast'

const STATUS_COLORS: Record<string, string> = {
  queued:    'bg-yellow-100 text-yellow-800',
  running:   'bg-blue-100 text-blue-800',
  done:      'bg-green-100 text-green-800',
  failed:    'bg-red-100 text-red-800',
  cancelled: 'bg-slate-100 text-slate-600',
  paused:    'bg-orange-100 text-orange-700',
}

const ALL_STATUSES: Array<Job['status'] | 'all'> = ['all', 'queued', 'running', 'paused', 'done', 'failed', 'cancelled']

export default function DashboardPage() {
  const { data: jobs = [], isLoading } = useQuery({ queryKey: ['jobs'], queryFn: listJobs, refetchInterval: 5000 })
  const qc = useQueryClient()

  async function handleStop(id: string) {
    if (!confirm('Stop this pipeline? It cannot be resumed.')) return
    try { await stopJob(id); qc.invalidateQueries({ queryKey: ['jobs'] }); toast.success('Pipeline stopped') }
    catch { toast.error('Failed to stop') }
  }
  async function handlePause(id: string) {
    try { await pauseJob(id); qc.invalidateQueries({ queryKey: ['jobs'] }); toast.success('Pipeline paused') }
    catch { toast.error('Failed to pause') }
  }
  async function handleResume(id: string) {
    try { await resumeJob(id); qc.invalidateQueries({ queryKey: ['jobs'] }); toast.success('Pipeline resumed') }
    catch { toast.error('Failed to resume') }
  }

  const [search, setSearch]   = useState('')
  const [status, setStatus]   = useState<Job['status'] | 'all'>('all')
  const [sortBy, setSortBy]   = useState<'created_at' | 'updated_at' | 'pipeline'>('created_at')
  const [sortDir, setSortDir] = useState<'desc' | 'asc'>('desc')

  const pipelines = useMemo(() => [...new Set(jobs.map(j => j.pipeline))].sort(), [jobs])

  const filtered = useMemo(() => {
    let result = jobs.filter(job => {
      const matchStatus   = status === 'all' || job.status === status
      const matchSearch   = search === '' ||
        job.pipeline.toLowerCase().includes(search.toLowerCase()) ||
        job.id.toLowerCase().includes(search.toLowerCase())
      return matchStatus && matchSearch
    })
    result = [...result].sort((a, b) => {
      let cmp = 0
      if (sortBy === 'pipeline') cmp = a.pipeline.localeCompare(b.pipeline)
      else cmp = new Date(a[sortBy]).getTime() - new Date(b[sortBy]).getTime()
      return sortDir === 'asc' ? cmp : -cmp
    })
    return result
  }, [jobs, search, status, sortBy, sortDir])

  function toggleSort(col: typeof sortBy) {
    if (sortBy === col) setSortDir(d => d === 'asc' ? 'desc' : 'asc')
    else { setSortBy(col); setSortDir('desc') }
  }

  const SortIcon = ({ col }: { col: typeof sortBy }) =>
    sortBy === col
      ? <span className="ml-1 text-indigo-600">{sortDir === 'asc' ? '↑' : '↓'}</span>
      : <span className="ml-1 text-slate-300">↕</span>

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-semibold">My Jobs</h2>
        <Link to="/submit" className="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-lg text-sm font-medium">
          + Run Pipeline
        </Link>
      </div>

      {/* Filter bar */}
      <div className="flex flex-wrap gap-3 mb-4">
        <input
          type="text"
          placeholder="Search by pipeline or job ID…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="border border-slate-300 rounded-lg px-3 py-1.5 text-sm w-64 focus:outline-none focus:ring-2 focus:ring-indigo-400"
        />

        <div className="flex rounded-lg border border-slate-300 overflow-hidden text-sm">
          {ALL_STATUSES.map(s => (
            <button
              key={s}
              onClick={() => setStatus(s)}
              className={`px-3 py-1.5 capitalize transition-colors ${
                status === s
                  ? 'bg-indigo-600 text-white font-medium'
                  : 'bg-white text-slate-600 hover:bg-slate-50'
              }`}
            >
              {s === 'all' ? `All (${jobs.length})` : `${s} (${jobs.filter(j => j.status === s).length})`}
            </button>
          ))}
        </div>

        {(search || status !== 'all') && (
          <button
            onClick={() => { setSearch(''); setStatus('all') }}
            className="text-sm text-slate-400 hover:text-slate-600 px-2"
          >
            Clear filters
          </button>
        )}
      </div>

      {isLoading && <p className="text-slate-500">Loading…</p>}

      {!isLoading && jobs.length === 0 && (
        <div className="text-center py-16 text-slate-400">
          No jobs yet. <Link to="/submit" className="text-indigo-600 hover:underline">Run your first pipeline.</Link>
        </div>
      )}

      {!isLoading && jobs.length > 0 && filtered.length === 0 && (
        <div className="text-center py-12 text-slate-400">
          No jobs match the current filters.
        </div>
      )}

      {filtered.length > 0 && (
        <div className="bg-white rounded-xl shadow overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-slate-50 border-b">
              <tr>
                <th className="text-left px-4 py-3 font-medium cursor-pointer select-none hover:text-indigo-600" onClick={() => toggleSort('pipeline')}>
                  Pipeline <SortIcon col="pipeline" />
                </th>
                <th className="text-left px-4 py-3 font-medium">Status</th>
                <th className="text-left px-4 py-3 font-medium cursor-pointer select-none hover:text-indigo-600" onClick={() => toggleSort('created_at')}>
                  Submitted <SortIcon col="created_at" />
                </th>
                <th className="text-left px-4 py-3 font-medium cursor-pointer select-none hover:text-indigo-600" onClick={() => toggleSort('updated_at')}>
                  Updated <SortIcon col="updated_at" />
                </th>
                <th />
              </tr>
            </thead>
            <tbody className="divide-y">
              {filtered.map((job) => (
                <tr key={job.id} className="hover:bg-slate-50">
                  <td className="px-4 py-3 font-mono text-xs">{job.pipeline}</td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_COLORS[job.status]}`}>
                      {job.status}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-slate-500">{new Date(job.created_at + 'Z').toLocaleString()}</td>
                  <td className="px-4 py-3 text-slate-500">{new Date(job.updated_at + 'Z').toLocaleString()}</td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <Link to={`/jobs/${job.id}`} className="text-indigo-600 hover:underline text-sm">Details</Link>
                      {job.status === 'running' && (
                        <>
                          <button onClick={() => handlePause(job.id)}
                            className="text-xs border border-orange-300 text-orange-600 hover:bg-orange-50 px-2 py-0.5 rounded transition-colors">
                            ⏸
                          </button>
                          <button onClick={() => handleStop(job.id)}
                            className="text-xs border border-red-300 text-red-600 hover:bg-red-50 px-2 py-0.5 rounded transition-colors">
                            ⏹
                          </button>
                        </>
                      )}
                      {job.status === 'paused' && (
                        <button onClick={() => handleResume(job.id)}
                          className="text-xs border border-green-300 text-green-600 hover:bg-green-50 px-2 py-0.5 rounded transition-colors">
                          ▶
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <div className="px-4 py-2 border-t text-xs text-slate-400">
            Showing {filtered.length} of {jobs.length} jobs
          </div>
        </div>
      )}
    </div>
  )
}
