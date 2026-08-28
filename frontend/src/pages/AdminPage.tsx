import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { listAdminUsers, listAdminProjects, listProjectAccess, grantProjectAccess, revokeProjectAccess, deleteUser } from '../api/admin'

// A user is considered "online" if we've heard from them within this window.
// The backend refreshes last_seen_at at most once per minute, so this needs
// enough slack to not flicker between requests.
const ONLINE_THRESHOLD_MS = 2 * 60 * 1000

function isOnline(lastSeenAt: string | null): boolean {
  if (!lastSeenAt) return false
  return Date.now() - new Date(lastSeenAt + 'Z').getTime() < ONLINE_THRESHOLD_MS
}

function formatLastSeen(lastSeenAt: string | null): string {
  if (!lastSeenAt) return 'never'
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(lastSeenAt + 'Z').getTime()) / 1000))
  if (seconds < 60) return 'just now'
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

export default function AdminPage() {
  const qc = useQueryClient()

  const { data: users = [], isLoading: usersLoading } = useQuery({
    queryKey: ['admin-users'],
    queryFn: listAdminUsers,
    refetchInterval: 30_000,
  })
  const { data: projects = [], isLoading: projectsLoading } = useQuery({ queryKey: ['admin-projects'], queryFn: listAdminProjects })
  const { data: grants = [], isLoading: grantsLoading } = useQuery({ queryKey: ['admin-project-access'], queryFn: listProjectAccess })

  const [username, setUsername] = useState('')
  const [projectName, setProjectName] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [search, setSearch] = useState('')

  const nonAdminUsers = useMemo(() => users.filter(u => !u.is_admin), [users])
  const onlineCount = useMemo(() => users.filter(u => isOnline(u.last_seen_at)).length, [users])

  const grantsByProject = useMemo(() => {
    const map = new Map<string, typeof grants>()
    for (const project of projects) map.set(project, [])
    for (const grant of grants) {
      const list = map.get(grant.project_name) ?? []
      list.push(grant)
      map.set(grant.project_name, list)
    }
    return map
  }, [projects, grants])

  const filteredProjects = useMemo(() => {
    if (!search) return projects
    const q = search.toLowerCase()
    return projects.filter(p =>
      p.toLowerCase().includes(q) ||
      (grantsByProject.get(p) ?? []).some(g => g.username.toLowerCase().includes(q))
    )
  }, [projects, search, grantsByProject])

  async function handleGrant(e: React.FormEvent) {
    e.preventDefault()
    if (!username || !projectName) return
    setSubmitting(true)
    try {
      await grantProjectAccess(username, projectName)
      toast.success(`Granted ${username} access to ${projectName}`)
      setUsername('')
      setProjectName('')
      qc.invalidateQueries({ queryKey: ['admin-project-access'] })
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Failed to grant access')
    } finally {
      setSubmitting(false)
    }
  }

  async function handleRevoke(grantId: string, username: string, projectName: string) {
    if (!confirm(`Revoke ${username}'s access to ${projectName}?`)) return
    try {
      await revokeProjectAccess(grantId)
      toast.success('Access revoked')
      qc.invalidateQueries({ queryKey: ['admin-project-access'] })
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Failed to revoke access')
    }
  }

  async function handleDeleteUser(userId: string, username: string) {
    if (!confirm(`Delete user ${username}? This cannot be undone.`)) return
    try {
      await deleteUser(userId)
      toast.success(`Deleted ${username}`)
      qc.invalidateQueries({ queryKey: ['admin-users'] })
      qc.invalidateQueries({ queryKey: ['admin-project-access'] })
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Failed to delete user')
    }
  }

  const loading = usersLoading || projectsLoading || grantsLoading

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-semibold">Project Access</h2>
        <p className="text-sm text-slate-400">
          {projects.length} project{projects.length === 1 ? '' : 's'} · {grants.length} grant{grants.length === 1 ? '' : 's'}
        </p>
      </div>

      <div className="bg-white rounded-xl shadow overflow-hidden mb-6">
        <div className="px-4 py-3 border-b bg-slate-50 flex items-center justify-between">
          <h3 className="font-semibold text-slate-700">Users</h3>
          <span className="text-xs text-slate-400">
            {onlineCount} online now
          </span>
        </div>
        {usersLoading ? (
          <p className="px-4 py-3 text-sm text-slate-400">Loading…</p>
        ) : users.length === 0 ? (
          <p className="px-4 py-3 text-sm text-slate-400 italic">No users found.</p>
        ) : (
          <div className="divide-y divide-slate-100">
            {users.map(u => {
              const online = isOnline(u.last_seen_at)
              return (
                <div key={u.id} className="flex items-center justify-between px-4 py-2.5 text-sm">
                  <span className="text-slate-700 flex items-center gap-2">
                    <span
                      className={`inline-block w-2 h-2 rounded-full ${online ? 'bg-emerald-500' : 'bg-slate-300'}`}
                      title={online ? 'Online' : 'Offline'}
                    />
                    {u.username} <span className="text-slate-400">({u.full_name})</span>
                    {u.is_admin && (
                      <span className="ml-1 text-xs bg-indigo-100 text-indigo-700 px-1.5 py-0.5 rounded">admin</span>
                    )}
                    <span className={`text-xs ${online ? 'text-emerald-600' : 'text-slate-400'}`}>
                      {online ? 'online' : `last seen ${formatLastSeen(u.last_seen_at)}`}
                    </span>
                  </span>
                  {!u.is_admin && (
                    <button onClick={() => handleDeleteUser(u.id, u.username)}
                      className="text-xs border border-red-300 text-red-600 hover:bg-red-50 px-2 py-0.5 rounded transition-colors">
                      Delete
                    </button>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </div>

      <div className="bg-white rounded-xl shadow p-4 mb-6">
        <h3 className="font-semibold text-slate-700 mb-3">Grant access</h3>
        <form onSubmit={handleGrant} className="flex flex-wrap items-end gap-3">
          <div className="flex-1 min-w-[180px]">
            <label className="text-xs text-slate-500 block mb-1">User</label>
            <select required value={username} onChange={e => setUsername(e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400">
              <option value="" disabled>Select a user…</option>
              {nonAdminUsers.map(u => (
                <option key={u.id} value={u.username}>{u.username} ({u.full_name})</option>
              ))}
            </select>
          </div>
          <div className="flex-1 min-w-[180px]">
            <label className="text-xs text-slate-500 block mb-1">Project</label>
            <select required value={projectName} onChange={e => setProjectName(e.target.value)}
              className="w-full border border-slate-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400">
              <option value="" disabled>Select a project…</option>
              {projects.map(p => <option key={p} value={p}>{p}</option>)}
            </select>
          </div>
          <button type="submit" disabled={submitting || !username || !projectName}
            className="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-lg text-sm font-medium disabled:opacity-50">
            {submitting ? 'Granting…' : '+ Grant access'}
          </button>
        </form>
        {nonAdminUsers.length === 0 && !usersLoading && (
          <p className="text-xs text-slate-400 mt-2">No non-admin users to grant access to yet.</p>
        )}
      </div>

      <input
        type="text"
        placeholder="Search by project or username…"
        value={search}
        onChange={e => setSearch(e.target.value)}
        className="border border-slate-300 rounded-lg px-3 py-1.5 text-sm w-64 mb-4 focus:outline-none focus:ring-2 focus:ring-indigo-400"
      />

      {loading && <p className="text-slate-500">Loading…</p>}

      {!loading && projects.length === 0 && (
        <div className="text-center py-16 text-slate-400">
          No preset projects found on disk yet.
        </div>
      )}

      {!loading && projects.length > 0 && filteredProjects.length === 0 && (
        <div className="text-center py-12 text-slate-400">
          No projects match "{search}".
        </div>
      )}

      {filteredProjects.length > 0 && (
        <div className="space-y-4">
          {filteredProjects.map(project => {
            const projectGrants = grantsByProject.get(project) ?? []
            return (
              <div key={project} className="bg-white rounded-xl shadow overflow-hidden">
                <div className="px-4 py-3 border-b bg-slate-50 flex items-center justify-between">
                  <span className="font-medium text-sm text-slate-700">{project}</span>
                  <span className="text-xs text-slate-400">
                    {projectGrants.length} user{projectGrants.length === 1 ? '' : 's'} with access
                  </span>
                </div>
                {projectGrants.length === 0 ? (
                  <p className="px-4 py-3 text-xs text-slate-400 italic">No users granted access yet.</p>
                ) : (
                  <div className="divide-y divide-slate-100">
                    {projectGrants.map(grant => (
                      <div key={grant.id} className="flex items-center justify-between px-4 py-2.5 text-sm">
                        <span className="text-slate-700">{grant.username}</span>
                        <button onClick={() => handleRevoke(grant.id, grant.username, project)}
                          className="text-xs border border-red-300 text-red-600 hover:bg-red-50 px-2 py-0.5 rounded transition-colors">
                          Revoke
                        </button>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
