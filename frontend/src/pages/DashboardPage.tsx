import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { listJobs, Job } from '../api/jobs'

const STATUS_COLORS: Record<Job['status'], string> = {
  queued:  'bg-yellow-100 text-yellow-800',
  running: 'bg-blue-100 text-blue-800',
  done:    'bg-green-100 text-green-800',
  failed:  'bg-red-100 text-red-800',
}

export default function DashboardPage() {
  const { data: jobs = [], isLoading } = useQuery({ queryKey: ['jobs'], queryFn: listJobs, refetchInterval: 5000 })

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-semibold">My Jobs</h2>
        <Link to="/submit" className="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-lg text-sm font-medium">
          + Run Pipeline
        </Link>
      </div>

      {isLoading && <p className="text-slate-500">Loading…</p>}

      {!isLoading && jobs.length === 0 && (
        <div className="text-center py-16 text-slate-400">
          No jobs yet. <Link to="/submit" className="text-indigo-600 hover:underline">Run your first pipeline.</Link>
        </div>
      )}

      {jobs.length > 0 && (
        <div className="bg-white rounded-xl shadow overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-slate-50 border-b">
              <tr>
                <th className="text-left px-4 py-3 font-medium">Pipeline</th>
                <th className="text-left px-4 py-3 font-medium">Status</th>
                <th className="text-left px-4 py-3 font-medium">Submitted</th>
                <th className="text-left px-4 py-3 font-medium">Updated</th>
                <th />
              </tr>
            </thead>
            <tbody className="divide-y">
              {jobs.map((job) => (
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
                    <Link to={`/jobs/${job.id}`} className="text-indigo-600 hover:underline">Details</Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
