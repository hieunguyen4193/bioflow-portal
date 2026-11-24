import { Routes, Route, Navigate } from 'react-router-dom'
import { useEffect } from 'react'
import { useAuthStore } from './store/auth'
import { getMe } from './api/auth'
import LoginPage from './pages/LoginPage'
import RegisterPage from './pages/RegisterPage'
import AdminPage from './pages/AdminPage'
import Layout from './components/Layout'

function RequireAuth({ children }: { children: React.ReactNode }) {
  const token = useAuthStore((s) => s.token)
  if (!token) return <Navigate to="/login" replace />
  return <>{children}</>
}

function RequireAdmin({ children }: { children: React.ReactNode }) {
  const user = useAuthStore((s) => s.user)
  if (!user) return null
  if (!user.is_admin) return <Navigate to="/explore" replace />
  return <>{children}</>
}

export default function App() {
  const { token, setUser } = useAuthStore()

  useEffect(() => {
    if (token) getMe().then(setUser).catch(() => {})
  }, [token])

  return (
    <Routes>
      <Route path="/login"    element={<LoginPage />} />
      <Route path="/register" element={<RegisterPage />} />
      <Route path="/" element={<RequireAuth><Layout /></RequireAuth>}>
        {/* Interactive data analysis (ExplorePage) is the only app page; Layout keeps it mounted. */}
        <Route index element={<Navigate to="/explore" replace />} />
        <Route path="explore" element={null} />
        <Route path="admin" element={<RequireAdmin><AdminPage /></RequireAdmin>} />
        <Route path="*" element={<Navigate to="/explore" replace />} />
      </Route>
    </Routes>
  )
}
