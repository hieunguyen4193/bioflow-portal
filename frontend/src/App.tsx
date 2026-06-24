import { Routes, Route, Navigate } from 'react-router-dom'
import { useEffect } from 'react'
import { useAuthStore } from './store/auth'
import { getMe } from './api/auth'
import LoginPage from './pages/LoginPage'
import RegisterPage from './pages/RegisterPage'
import DashboardPage from './pages/DashboardPage'
import SubmitJobPage from './pages/SubmitJobPage'
import JobDetailPage from './pages/JobDetailPage'
import Layout from './components/Layout'

function RequireAuth({ children }: { children: React.ReactNode }) {
  const token = useAuthStore((s) => s.token)
  if (!token) return <Navigate to="/login" replace />
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
        <Route index element={<DashboardPage />} />
        <Route path="submit" element={<SubmitJobPage />} />
        <Route path="jobs/:id" element={<JobDetailPage />} />
      </Route>
    </Routes>
  )
}
