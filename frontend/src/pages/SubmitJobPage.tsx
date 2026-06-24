import { useState, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { useDropzone } from 'react-dropzone'
import { useQuery } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { listPipelines, uploadFiles, submitJob } from '../api/jobs'

const REQUIRED_FILES = ['barcodes.tsv.gz', 'features.tsv.gz', 'matrix.mtx.gz']

export default function SubmitJobPage() {
  const navigate = useNavigate()
  const { data: pipelines = [] } = useQuery({ queryKey: ['pipelines'], queryFn: listPipelines })
  const [selectedPipeline, setSelectedPipeline] = useState('seurat_from_10x')
  const [files, setFiles] = useState<File[]>([])
  const [params, setParams] = useState<Record<string, string>>({
    sample_name: 'sample',
    min_cells: '3',
    min_features: '200',
    max_features: '5000',
    max_mt_pct: '20',
  })
  const [uploading, setUploading] = useState(false)
  const [uploadProgress, setUploadProgress] = useState(0)

  const onDrop = useCallback((accepted: File[]) => {
    setFiles((prev) => {
      const names = new Set(prev.map((f) => f.name))
      return [...prev, ...accepted.filter((f) => !names.has(f.name))]
    })
  }, [])

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: { 'application/gzip': ['.gz'], 'text/plain': ['.tsv', '.mtx'] },
    multiple: true,
  })

  const missingFiles = REQUIRED_FILES.filter((req) => !files.some((f) => f.name === req))

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (missingFiles.length > 0) {
      toast.error(`Missing: ${missingFiles.join(', ')}`)
      return
    }
    setUploading(true)
    try {
      setUploadProgress(20)
      const { batch_id } = await uploadFiles(files)
      setUploadProgress(70)
      const job = await submitJob(selectedPipeline, batch_id, params)
      setUploadProgress(100)
      toast.success('Job submitted!')
      navigate(`/jobs/${job.id}`)
    } catch (err: any) {
      toast.error(err.response?.data?.detail || 'Submission failed')
    } finally {
      setUploading(false)
      setUploadProgress(0)
    }
  }

  const currentPipeline = pipelines.find((p: any) => p.id === selectedPipeline)

  return (
    <div className="max-w-2xl">
      <h2 className="text-xl font-semibold mb-6">Run Pipeline</h2>

      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Pipeline selector */}
        <div className="bg-white rounded-xl shadow p-5">
          <h3 className="font-medium mb-3">1. Select Pipeline</h3>
          <div className="space-y-2">
            {pipelines.map((p: any) => (
              <label key={p.id} className="flex items-start gap-3 cursor-pointer">
                <input type="radio" name="pipeline" value={p.id} checked={selectedPipeline === p.id}
                  onChange={() => setSelectedPipeline(p.id)} className="mt-1" />
                <div>
                  <div className="font-medium text-sm">{p.name}</div>
                  <div className="text-xs text-slate-500">{p.description}</div>
                </div>
              </label>
            ))}
          </div>
        </div>

        {/* File upload */}
        <div className="bg-white rounded-xl shadow p-5">
          <h3 className="font-medium mb-3">2. Upload Input Files</h3>
          <p className="text-xs text-slate-500 mb-3">
            Required: <code>barcodes.tsv.gz</code>, <code>features.tsv.gz</code>, <code>matrix.mtx.gz</code>
          </p>

          <div {...getRootProps()}
            className={`border-2 border-dashed rounded-lg p-6 text-center cursor-pointer transition-colors ${
              isDragActive ? 'border-indigo-400 bg-indigo-50' : 'border-slate-300 hover:border-indigo-300'
            }`}>
            <input {...getInputProps()} />
            <p className="text-sm text-slate-500">
              {isDragActive ? 'Drop the files here…' : 'Drag & drop files here, or click to browse'}
            </p>
          </div>

          {files.length > 0 && (
            <ul className="mt-3 space-y-1">
              {files.map((f) => (
                <li key={f.name} className="flex items-center justify-between text-sm">
                  <span className="flex items-center gap-2">
                    <span className={REQUIRED_FILES.includes(f.name) ? 'text-green-600' : 'text-slate-500'}>
                      {REQUIRED_FILES.includes(f.name) ? '✓' : '·'}
                    </span>
                    {f.name}
                  </span>
                  <span className="text-slate-400">{(f.size / 1024 / 1024).toFixed(1)} MB</span>
                </li>
              ))}
            </ul>
          )}

          {missingFiles.length > 0 && files.length > 0 && (
            <p className="mt-2 text-xs text-amber-600">Still needed: {missingFiles.join(', ')}</p>
          )}
        </div>

        {/* Parameters */}
        {currentPipeline?.params && (
          <div className="bg-white rounded-xl shadow p-5">
            <h3 className="font-medium mb-3">3. Parameters</h3>
            <div className="grid grid-cols-2 gap-4">
              {currentPipeline.params.map((p: any) => (
                <div key={p.key}>
                  <label className="block text-xs font-medium mb-1">{p.label}</label>
                  <input
                    type={p.type === 'str' ? 'text' : 'number'}
                    step={p.type === 'float' ? '0.1' : '1'}
                    value={params[p.key] ?? p.default}
                    onChange={(e) => setParams((prev) => ({ ...prev, [p.key]: e.target.value }))}
                    className="w-full border rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
                  />
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Progress bar */}
        {uploading && (
          <div className="w-full bg-slate-200 rounded-full h-2">
            <div className="bg-indigo-500 h-2 rounded-full transition-all duration-300" style={{ width: `${uploadProgress}%` }} />
          </div>
        )}

        <button type="submit" disabled={uploading}
          className="w-full bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg py-2.5 font-medium disabled:opacity-50">
          {uploading ? 'Uploading & submitting…' : 'Submit Job'}
        </button>
      </form>
    </div>
  )
}
