import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import {
  clearPipelineOverride,
  listAdminUsers,
  listPipelineVisibility,
  setPipelineEnabled,
  setPipelineOverride,
  type PipelineVisibility,
} from '../api/admin'

// Resolved visibility for one user, mirroring app.services.pipeline_access:
// an explicit override wins, otherwise the global switch decides.
function effectiveLabel(pipeline: PipelineVisibility, allowed: boolean): string {
  if (allowed === pipeline.is_enabled) return allowed ? 'visible (same as default)' : 'hidden (same as default)'
  return allowed ? 'visible — override' : 'hidden — override'
}

function PipelineCard({ pipeline }: { pipeline: PipelineVisibility }) {
  const qc = useQueryClient()
  const { data: users = [] } = useQuery({ queryKey: ['admin-users'], queryFn: listAdminUsers })
  const nonAdminUsers = useMemo(() => users.filter((u) => !u.is_admin), [users])

  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [username, setUsername] = useState('')
  const [allowed, setAllowed] = useState('true')

  function refresh() {
    qc.invalidateQueries({ queryKey: ['admin-pipelines'] })
  }

  async function handleToggle() {
    setBusy(true)
    try {
      await setPipelineEnabled(pipeline.id, !pipeline.is_enabled)
      toast.success(`${pipeline.name} is now ${pipeline.is_enabled ? 'hidden' : 'visible'} by default`)
      refresh()
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Failed to update pipeline')
    } finally {
      setBusy(false)
    }
  }

  async function handleAddOverride(e: React.FormEvent) {
    e.preventDefault()
    if (!username) return
    setBusy(true)
    try {
      await setPipelineOverride(username, pipeline.id, allowed === 'true')
      toast.success(`${username}: ${pipeline.name} ${allowed === 'true' ? 'shown' : 'hidden'}`)
      setUsername('')
      refresh()
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Failed to set override')
    } finally {
      setBusy(false)
    }
  }

  async function handleClear(overrideId: string, who: string) {
    if (!confirm(`Clear ${who}'s override for ${pipeline.name}? They fall back to the default.`)) return
    try {
      await clearPipelineOverride(overrideId)
      toast.success('Override cleared')
      refresh()
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Failed to clear override')
    }
  }

  const overrideUsernames = new Set(pipeline.overrides.map((o) => o.username))
  const addableUsers = nonAdminUsers.filter((u) => !overrideUsernames.has(u.username))

  return (
    <div className={`rounded-xl shadow border transition-colors ${pipeline.is_enabled ? 'bg-white border-slate-200' : 'bg-slate-50 border-slate-200'}`}>
      <div className="flex items-center gap-3 px-4 py-3 cursor-pointer select-none" onClick={() => setOpen((o) => !o)}>
        <div
          onClick={(e) => { e.stopPropagation(); if (!busy) handleToggle() }}
          className={`relative flex-shrink-0 w-10 h-5 rounded-full transition-colors cursor-pointer ${
            pipeline.is_enabled ? 'bg-indigo-500' : 'bg-slate-300'
          } ${busy ? 'opacity-50' : ''}`}
          title={pipeline.is_enabled ? 'Click to hide from the Run Pipeline section' : 'Click to show in the Run Pipeline section'}
        >
          <span className={`absolute top-0.5 left-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform ${pipeline.is_enabled ? 'translate-x-5' : ''}`} />
        </div>

        <div className="flex-1 min-w-0">
          <span className={`font-medium text-sm ${pipeline.is_enabled ? 'text-slate-800' : 'text-slate-500'}`}>
            {pipeline.name}
          </span>
          <span className="ml-2 text-xs text-slate-400">
            {pipeline.is_enabled ? 'visible to everyone' : 'hidden by default'}
          </span>
        </div>

        {pipeline.overrides.length > 0 && (
          <span className="text-xs bg-amber-100 text-amber-700 px-1.5 py-0.5 rounded">
            {pipeline.overrides.length} override{pipeline.overrides.length === 1 ? '' : 's'}
          </span>
        )}

        <svg className={`w-4 h-4 text-slate-400 transition-transform ${open ? 'rotate-180' : ''}`}
             fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </div>

      {open && (
        <div className="px-4 pb-4 border-t border-slate-100 pt-3">
          <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Per-user overrides</h4>

          {pipeline.overrides.length === 0 ? (
            <p className="text-xs text-slate-400 italic mb-3">
              None — every non-admin user follows the default above.
            </p>
          ) : (
            <div className="divide-y divide-slate-100 mb-3">
              {pipeline.overrides.map((o) => (
                <div key={o.id} className="flex items-center justify-between py-2 text-sm">
                  <span className="text-slate-700">
                    {o.username} <span className="text-slate-400">({o.full_name})</span>
                    <span className={`ml-2 text-xs px-1.5 py-0.5 rounded ${o.allowed ? 'bg-emerald-100 text-emerald-700' : 'bg-red-100 text-red-700'}`}>
                      {effectiveLabel(pipeline, o.allowed)}
                    </span>
                  </span>
                  <button onClick={() => handleClear(o.id, o.username)}
                    className="text-xs border border-slate-300 text-slate-600 hover:bg-slate-100 px-2 py-0.5 rounded transition-colors">
                    Clear
                  </button>
                </div>
              ))}
            </div>
          )}

          <form onSubmit={handleAddOverride} className="flex flex-wrap items-end gap-2">
            <div className="flex-1 min-w-[180px]">
              <label className="text-xs text-slate-500 block mb-1">User</label>
              <select value={username} onChange={(e) => setUsername(e.target.value)}
                className="w-full border border-slate-300 rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400">
                <option value="" disabled>Select a user…</option>
                {addableUsers.map((u) => (
                  <option key={u.id} value={u.username}>{u.username} ({u.full_name})</option>
                ))}
              </select>
            </div>
            <div className="min-w-[140px]">
              <label className="text-xs text-slate-500 block mb-1">Visibility</label>
              <select value={allowed} onChange={(e) => setAllowed(e.target.value)}
                className="w-full border border-slate-300 rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400">
                <option value="true">Show</option>
                <option value="false">Hide</option>
              </select>
            </div>
            <button type="submit" disabled={busy || !username}
              className="bg-indigo-600 hover:bg-indigo-700 text-white px-3 py-1.5 rounded-lg text-sm font-medium disabled:opacity-50">
              + Set override
            </button>
          </form>
          {addableUsers.length === 0 && nonAdminUsers.length > 0 && (
            <p className="text-xs text-slate-400 mt-2">Every non-admin user already has an override here.</p>
          )}
        </div>
      )}
    </div>
  )
}

export default function PipelineVisibilityPanel() {
  const { data: pipelines = [], isLoading } = useQuery({
    queryKey: ['admin-pipelines'],
    queryFn: listPipelineVisibility,
  })

  const hiddenCount = pipelines.filter((p) => !p.is_enabled).length

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <h2 className="text-xl font-semibold">Pipeline Visibility</h2>
        <p className="text-sm text-slate-400">
          {pipelines.length} pipeline{pipelines.length === 1 ? '' : 's'} · {hiddenCount} hidden by default
        </p>
      </div>
      <p className="text-sm text-slate-500 mb-6">
        The toggle sets whether a pipeline shows up in <span className="font-medium">Run Pipeline</span> for
        non-admin users. A per-user override beats the toggle in either direction. Admins always see every
        pipeline.
      </p>

      {isLoading ? (
        <p className="text-slate-500">Loading…</p>
      ) : pipelines.length === 0 ? (
        <div className="text-center py-16 text-slate-400">No pipelines in the registry.</div>
      ) : (
        <div className="space-y-3">
          {pipelines.map((p) => <PipelineCard key={p.id} pipeline={p} />)}
        </div>
      )}
    </div>
  )
}
