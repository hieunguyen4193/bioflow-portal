import { useParams, Link } from 'react-router-dom'
import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { getJob, listOutputFiles, downloadUrl, getPipeline, stopJob, pauseJob, resumeJob, Job, Pipeline } from '../api/jobs'
import toast from 'react-hot-toast'

function buildParamIndex(pipeline: Pipeline | undefined) {
  const index: Record<string, { stepLabel: string; paramLabel: string }> = {}
  if (!pipeline) return index
  for (const step of pipeline.steps) {
    for (const p of step.params) {
      index[p.key] = { stepLabel: step.label, paramLabel: p.label }
    }
    if (step.run_key) index[step.run_key] = { stepLabel: step.label, paramLabel: 'Run this step' }
  }
  return index
}

function downloadParamsCSV(job: Job, pipeline: Pipeline | undefined) {
  const index = buildParamIndex(pipeline)
  const metaRows = [
    ['', 'Job metadata', 'job_id',    'Job ID',    job.id],
    ['', 'Job metadata', 'pipeline',  'Pipeline',  job.pipeline],
    ['', 'Job metadata', 'status',    'Status',    job.status],
    ['', 'Job metadata', 'submitted', 'Submitted', new Date(job.created_at + 'Z').toISOString()],
    ['', 'Job metadata', 'updated',   'Updated',   new Date(job.updated_at + 'Z').toISOString()],
  ]
  const paramRows = Object.entries(job.params).map(([k, v]) => {
    const info = index[k]
    return [info?.stepLabel ?? '', info?.stepLabel ?? 'General', k, info?.paramLabel ?? k, String(v)]
  })
  const header = 'step,step_label,parameter_key,parameter_label,value'
  const rows   = [...metaRows, ...paramRows]
    .map(cols => cols.map(c => JSON.stringify(c)).join(','))
    .join('\n')
  const blob = new Blob([`${header}\n${rows}`], { type: 'text/csv' })
  const url  = URL.createObjectURL(blob)
  const a    = document.createElement('a')
  a.href     = url
  a.download = `params_${job.id}.csv`
  a.click()
  URL.revokeObjectURL(url)
}

const STATUS_COLORS: Record<string, string> = {
  queued:    'bg-yellow-100 text-yellow-800',
  running:   'bg-blue-100 text-blue-800',
  done:      'bg-green-100 text-green-800',
  failed:    'bg-red-100 text-red-800',
  cancelled: 'bg-slate-100 text-slate-600',
  paused:    'bg-orange-100 text-orange-700',
}

export default function JobDetailPage() {
  const { id } = useParams<{ id: string }>()
  const qc = useQueryClient()

  const { data: job } = useQuery({
    queryKey: ['job', id],
    queryFn: () => getJob(id!),
    refetchInterval: (query) => {
      const status = query.state.data?.status
      return status === 'queued' || status === 'running' || status === 'paused' ? 3000 : false
    },
  })

  async function handleStop() {
    if (!confirm('Stop this pipeline? It cannot be resumed.')) return
    try { await stopJob(id!); qc.invalidateQueries({ queryKey: ['job', id] }); toast.success('Pipeline stopped') }
    catch { toast.error('Failed to stop') }
  }

  async function handlePause() {
    try { await pauseJob(id!); qc.invalidateQueries({ queryKey: ['job', id] }); toast.success('Pipeline paused — can be resumed later') }
    catch { toast.error('Failed to pause') }
  }

  async function handleResume() {
    try { await resumeJob(id!); qc.invalidateQueries({ queryKey: ['job', id] }); toast.success('Pipeline resumed') }
    catch { toast.error('Failed to resume') }
  }

  const { data: pipeline } = useQuery({
    queryKey: ['pipeline', job?.pipeline],
    queryFn: () => getPipeline(job!.pipeline),
    enabled: !!job?.pipeline,
  })

  const { data: files = [] } = useQuery({
    queryKey: ['job-files', id],
    queryFn: () => listOutputFiles(id!),
    enabled: job?.status === 'done',
  })

  const [openGroups, setOpenGroups] = useState<Record<string, boolean>>({})

  if (!job) return <p className="text-slate-500">Loading…</p>

  const imageFiles = files.filter((f) => f.name.endsWith('.png') || f.name.endsWith('.pdf'))
  const dataFiles  = files.filter((f) => !f.name.endsWith('.png'))

  // Group data files by top-level directory
  const fileGroups = dataFiles.reduce<Record<string, typeof dataFiles>>((acc, f) => {
    const parts = f.name.split('/')
    const group = parts.length > 1 ? parts[0] : '(root)'
    acc[group] = acc[group] ?? []
    acc[group].push(f)
    return acc
  }, {})
  const groupNames = Object.keys(fileGroups).sort()
  const manyFiles  = dataFiles.length > 20
  const isOpen = (g: string) => openGroups[g] ?? !manyFiles
  const toggleGroup = (g: string) => setOpenGroups(prev => ({ ...prev, [g]: !isOpen(g) }))

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Link to="/" className="text-slate-400 hover:text-slate-600 text-sm">← Jobs</Link>
        <h2 className="text-xl font-semibold">{job.pipeline}</h2>
        <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_COLORS[job.status]}`}>
          {job.status}
        </span>
        <div className="ml-auto flex items-center gap-2">
          {job.status === 'running' && (
            <>
              <button onClick={handlePause}
                className="text-sm border border-orange-300 text-orange-600 hover:bg-orange-50 px-3 py-1.5 rounded-lg transition-colors">
                ⏸ Pause
              </button>
              <button onClick={handleStop}
                className="text-sm border border-red-300 text-red-600 hover:bg-red-50 px-3 py-1.5 rounded-lg transition-colors">
                ⏹ Stop
              </button>
            </>
          )}
          {job.status === 'paused' && (
            <button onClick={handleResume}
              className="text-sm border border-green-300 text-green-600 hover:bg-green-50 px-3 py-1.5 rounded-lg transition-colors">
              ▶ Resume
            </button>
          )}
          <button
            onClick={() => downloadParamsCSV(job, pipeline)}
            className="flex items-center gap-1.5 text-sm border border-slate-300 hover:border-indigo-400 hover:text-indigo-600 px-3 py-1.5 rounded-lg transition-colors"
          >
            ⬇ Download Parameters
          </button>
        </div>
      </div>

      {/* Meta */}
      <div className="bg-white rounded-xl shadow p-5 text-sm grid grid-cols-2 gap-3">
        <div><span className="text-slate-500">Job ID</span><br /><code className="text-xs">{job.id}</code></div>
        <div><span className="text-slate-500">Submitted</span><br />{new Date(job.created_at + 'Z').toLocaleString()}</div>
        <div><span className="text-slate-500">Updated</span><br />{new Date(job.updated_at + 'Z').toLocaleString()}</div>
        <div className="col-span-2">
          <span className="text-slate-500">Parameters</span>
          <div className="mt-2 rounded-lg border border-slate-200 overflow-hidden">
            <table className="w-full text-xs">
              <thead className="bg-slate-50 border-b">
                <tr>
                  <th className="text-left px-3 py-2 font-medium text-slate-600">Step</th>
                  <th className="text-left px-3 py-2 font-medium text-slate-600">Parameter</th>
                  <th className="text-left px-3 py-2 font-medium text-slate-600">Value</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {(() => {
                  const index = buildParamIndex(pipeline)
                  return Object.entries(job.params).map(([k, v]) => {
                    const info = index[k]
                    return (
                      <tr key={k} className="hover:bg-slate-50">
                        <td className="px-3 py-1.5 text-slate-400 whitespace-nowrap">{info?.stepLabel ?? '—'}</td>
                        <td className="px-3 py-1.5 text-slate-700">
                          <span className="font-medium">{info?.paramLabel ?? k}</span>
                          <span className="ml-1.5 text-slate-400 font-mono">({k})</span>
                        </td>
                        <td className="px-3 py-1.5 font-mono text-slate-500 break-all">{String(v)}</td>
                      </tr>
                    )
                  })
                })()}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* QC plots */}
      {imageFiles.length > 0 && (
        <div className="bg-white rounded-xl shadow p-5">
          <h3 className="font-medium mb-4">QC Plots</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {imageFiles.map((f) => (
              <div key={f.name}>
                <p className="text-xs text-slate-500 mb-1">{f.name}</p>
                <img src={downloadUrl(job.id, f.name)} alt={f.name}
                  className="w-full rounded border" />
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Output files */}
      {dataFiles.length > 0 && (
        <div className="bg-white rounded-xl shadow p-5">
          <div className="flex items-center justify-between mb-3">
            <h3 className="font-medium">Output Files <span className="text-slate-400 font-normal text-sm">({dataFiles.length})</span></h3>
            {manyFiles && (
              <div className="flex gap-2">
                <button onClick={() => setOpenGroups(Object.fromEntries(groupNames.map(g => [g, true])))}
                  className="text-xs text-indigo-600 hover:underline">Expand all</button>
                <span className="text-slate-300">|</span>
                <button onClick={() => setOpenGroups(Object.fromEntries(groupNames.map(g => [g, false])))}
                  className="text-xs text-indigo-600 hover:underline">Collapse all</button>
              </div>
            )}
          </div>
          <div className="space-y-1">
            {groupNames.map(group => (
              <div key={group} className="border rounded-lg overflow-hidden">
                <button
                  onClick={() => toggleGroup(group)}
                  className="w-full flex items-center justify-between px-3 py-2 bg-slate-50 hover:bg-slate-100 text-sm font-medium text-left"
                >
                  <span className="font-mono">{group} <span className="text-slate-400 font-normal">({fileGroups[group].length})</span></span>
                  <span className="text-slate-400">{isOpen(group) ? '▲' : '▼'}</span>
                </button>
                {isOpen(group) && (
                  <ul className="divide-y text-sm">
                    {fileGroups[group].map((f) => (
                      <li key={f.name} className="flex items-center justify-between px-3 py-2">
                        <span className="font-mono text-xs text-slate-600">{f.name.split('/').slice(1).join('/') || f.name}</span>
                        <div className="flex items-center gap-3 shrink-0 ml-4">
                          <span className="text-slate-400 text-xs">{(f.size / 1024 / 1024).toFixed(2)} MB</span>
                          <a href={downloadUrl(job.id, f.name)} download
                            className="text-indigo-600 hover:underline text-xs font-medium">
                            Download
                          </a>
                        </div>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Log */}
      {job.log && (
        <div className="bg-white rounded-xl shadow p-5">
          <h3 className="font-medium mb-3">Log</h3>
          <pre className="text-xs bg-slate-950 text-green-400 rounded-lg p-4 overflow-auto max-h-96 whitespace-pre-wrap">
            {job.log}
          </pre>
        </div>
      )}

      {(job.status === 'queued' || job.status === 'running') && (
        <p className="text-sm text-slate-500 animate-pulse">Pipeline is {job.status}… page auto-refreshes every 3 s.</p>
      )}
    </div>
  )
}
