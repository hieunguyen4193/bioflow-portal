import { Outlet, NavLink, useNavigate, useLocation } from 'react-router-dom'
import { useAuthStore } from '../store/auth'

export default function Layout() {
  const { user, logout } = useAuthStore()
  const navigate  = useNavigate()
  const location  = useLocation()
  const isExplore = location.pathname === '/explore'

  function handleLogout() {
    logout()
    navigate('/login')
  }

  return (
    <div className="h-screen flex flex-col overflow-hidden">
      <header className="bg-indigo-700 text-white px-6 py-3 flex items-center justify-between shadow">
        <div className="flex items-center gap-6">
          <span className="font-bold text-lg tracking-tight">BioFlow Portal</span>
          <nav className="flex gap-4 text-sm">
            <NavLink to="/" end className={({ isActive }) => isActive ? 'underline' : 'opacity-80 hover:opacity-100'}>
              Dashboard
            </NavLink>
            <NavLink to="/submit" className={({ isActive }) => isActive ? 'underline' : 'opacity-80 hover:opacity-100'}>
              Run Pipeline
            </NavLink>
            <NavLink to="/explore" className={({ isActive }) => isActive ? 'underline' : 'opacity-80 hover:opacity-100'}>
              Explore gene expression (Seurat)
            </NavLink>
          </nav>
        </div>
        <div className="flex items-center gap-3 text-sm">
          <span className="opacity-80">{user?.email}</span>
          <button onClick={handleLogout} className="bg-white/20 hover:bg-white/30 px-3 py-1 rounded">
            Logout
          </button>
        </div>
      </header>
      <main className={isExplore ? 'flex-1 overflow-hidden' : 'flex-1 overflow-y-auto max-w-5xl mx-auto w-full px-4 py-8'}>
        <Outlet />
      </main>
    </div>
  )
}
