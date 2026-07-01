import { useState } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { register } from '../api/auth'
import toast from 'react-hot-toast'

// Excludes visually ambiguous characters (0/O, 1/l/I) so a generated password is easy to retype if needed.
const PASSWORD_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*-_'

function generatePassword(length = 16): string {
  const values = new Uint32Array(length)
  window.crypto.getRandomValues(values)
  return Array.from(values, (n) => PASSWORD_CHARS[n % PASSWORD_CHARS.length]).join('')
}

export default function RegisterPage() {
  const [username, setUsername] = useState('')
  const [email, setEmail] = useState('')
  const [fullName, setFullName] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()

  function handleGeneratePassword() {
    const generated = generatePassword()
    setPassword(generated)
    setShowPassword(true)
    navigator.clipboard?.writeText(generated).then(
      () => toast.success('Generated password copied to clipboard'),
      () => {}
    )
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    try {
      await register(username, fullName, password, email)
      toast.success('Account created — please sign in')
      navigate('/login')
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Registration failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-100">
      <div className="bg-white shadow rounded-xl p-8 w-full max-w-sm">
        <h1 className="text-2xl font-bold text-indigo-700 mb-6">Create Account</h1>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium mb-1">Username</label>
            <input required minLength={3} maxLength={32} pattern="[a-zA-Z0-9_.-]+"
              title="Letters, numbers, underscores, dots, and hyphens only"
              value={username} onChange={(e) => setUsername(e.target.value)}
              className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          </div>
          <div>
            <label className="block text-sm font-medium mb-1">Full name</label>
            <input required value={fullName} onChange={(e) => setFullName(e.target.value)}
              className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          </div>
          <div>
            <label className="block text-sm font-medium mb-1">Email <span className="text-slate-400 font-normal">(optional)</span></label>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)}
              className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          </div>
          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="block text-sm font-medium">Password</label>
              <button type="button" onClick={handleGeneratePassword}
                className="text-xs text-indigo-600 hover:underline font-medium">
                Generate random password
              </button>
            </div>
            <div className="relative">
              <input type={showPassword ? 'text' : 'password'} required minLength={8}
                value={password} onChange={(e) => setPassword(e.target.value)}
                className="w-full border rounded-lg px-3 py-2 pr-16 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
              <button type="button" onClick={() => setShowPassword((v) => !v)}
                className="absolute inset-y-0 right-0 px-3 text-xs text-slate-400 hover:text-slate-600">
                {showPassword ? 'Hide' : 'Show'}
              </button>
            </div>
          </div>
          <button type="submit" disabled={loading}
            className="w-full bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg py-2 font-medium disabled:opacity-50">
            {loading ? 'Creating…' : 'Create account'}
          </button>
        </form>
        <p className="mt-4 text-sm text-center text-slate-500">
          Already have an account? <Link to="/login" className="text-indigo-600 hover:underline">Sign in</Link>
        </p>
      </div>
    </div>
  )
}
