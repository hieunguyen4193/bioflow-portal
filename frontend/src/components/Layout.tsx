import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import { useAuthStore } from '../store/auth'

export default function Layout() {
  const { user, logout } = useAuthStore()
  const navigate = useNavigate()

  function handleLogout() {
    logout()
    navigate('/login')
  }

  return (
    <div className="min-h-screen flex flex-col">
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
          </nav>
        </div>
        <div className="flex items-center gap-3 text-sm">
          <span className="opacity-80">{user?.email}</span>
          <button onClick={handleLogout} className="bg-white/20 hover:bg-white/30 px-3 py-1 rounded">
            Logout
          </button>
        </div>
      </header>
      <main className="flex-1 max-w-5xl mx-auto w-full px-4 py-8">
        <Outlet />
      </main>
    </div>
  )
}
