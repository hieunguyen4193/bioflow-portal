import { useParams, Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { getJob, listOutputFiles, downloadUrl } from '../api/jobs'

const STATUS_COLORS: Record<string, string> = {
  queued:  'bg-yellow-100 text-yellow-800',
  running: 'bg-blue-100 text-blue-800',
  done:    'bg-green-100 text-green-800',
  failed:  'bg-red-100 text-red-800',
}

export default function JobDetailPage() {
  const { id } = useParams<{ id: string }>()

  const { data: job } = useQuery({
    queryKey: ['job', id],
    queryFn: () => getJob(id!),
    refetchInterval: (query) => {
      const status = query.state.data?.status
      return status === 'queued' || status === 'running' ? 3000 : false
    },
  })

  const { data: files = [] } = useQuery({
    queryKey: ['job-files', id],
    queryFn: () => listOutputFiles(id!),
    enabled: job?.status === 'done',
  })

  if (!job) return <p className="text-slate-500">Loading…</p>

  const imageFiles = files.filter((f) => f.name.endsWith('.png') || f.name.endsWith('.pdf'))
  const dataFiles  = files.filter((f) => !f.name.endsWith('.png'))

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Link to="/" className="text-slate-400 hover:text-slate-600 text-sm">← Jobs</Link>
        <h2 className="text-xl font-semibold">{job.pipeline}</h2>
        <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_COLORS[job.status]}`}>
          {job.status}
        </span>
      </div>

      {/* Meta */}
      <div className="bg-white rounded-xl shadow p-5 text-sm grid grid-cols-2 gap-3">
        <div><span className="text-slate-500">Job ID</span><br /><code className="text-xs">{job.id}</code></div>
        <div><span className="text-slate-500">Submitted</span><br />{new Date(job.created_at + 'Z').toLocaleString()}</div>
        <div><span className="text-slate-500">Updated</span><br />{new Date(job.updated_at + 'Z').toLocaleString()}</div>
        <div><span className="text-slate-500">Parameters</span><br />
          {Object.entries(job.params).map(([k, v]) => (
            <span key={k} className="inline-block mr-2 text-xs bg-slate-100 px-1 rounded">{k}={String(v)}</span>
          ))}
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
          <h3 className="font-medium mb-3">Output Files</h3>
          <ul className="divide-y text-sm">
            {dataFiles.map((f) => (
              <li key={f.name} className="flex items-center justify-between py-2">
                <span className="font-mono text-xs">{f.name}</span>
                <div className="flex items-center gap-3">
                  <span className="text-slate-400 text-xs">{(f.size / 1024 / 1024).toFixed(2)} MB</span>
                  <a href={downloadUrl(job.id, f.name)} download
                    className="text-indigo-600 hover:underline text-xs font-medium">
                    Download
                  </a>
                </div>
              </li>
            ))}
          </ul>
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
