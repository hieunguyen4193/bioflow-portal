import { useState, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { useDropzone } from 'react-dropzone'
import { useQuery } from '@tanstack/react-query'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import toast from 'react-hot-toast'
import { listPipelines, getPipelineReadme, uploadFiles, submitJob } from '../api/jobs'

const REQUIRED_FILES = ['barcodes.tsv.gz', 'features.tsv.gz', 'matrix.mtx.gz']

// ── Small reusable field renderer ────────────────────────────────────────────
function ParamField({
  p,
  value,
  onChange,
}: {
  p: any
  value: string
  onChange: (val: string) => void
}) {
  const base = 'w-full border rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400'

  if (p.type === 'bool' || p.type === 'select') {
    const options =
      p.type === 'bool'
        ? [{ value: 'true', label: 'True' }, { value: 'false', label: 'False' }]
        : (p.options as string[]).map((o) => ({ value: o, label: o }))
    return (
      <select value={value} onChange={(e) => onChange(e.target.value)} className={base}>
        {options.map((o) => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    )
  }

  return (
    <input
      type={p.type === 'str' ? 'text' : 'number'}
      step={p.type === 'float' ? '0.01' : '1'}
      value={value}
      placeholder={value === '' ? 'leave blank to skip' : undefined}
      onChange={(e) => onChange(e.target.value)}
      className={base}
    />
  )
}

// ── Step panel with toggle header ─────────────────────────────────────────────
function StepPanel({
  step,
  params,
  setParam,
}: {
  step: any
  params: Record<string, string>
  setParam: (key: string, val: string) => void
}) {
  const alwaysRuns = step.run_key === null
  const enabled = alwaysRuns || (params[step.run_key] ?? 'true') === 'true'
  const [open, setOpen] = useState(true)

  function toggleRun() {
    if (!alwaysRuns) setParam(step.run_key, enabled ? 'false' : 'true')
  }

  return (
    <div className={`rounded-xl shadow border transition-colors ${enabled ? 'bg-white border-slate-200' : 'bg-slate-50 border-slate-200 opacity-60'}`}>
      <div className="flex items-center gap-3 px-5 py-3 cursor-pointer select-none"
           onClick={() => setOpen((o) => !o)}>
        <div
          onClick={(e) => { e.stopPropagation(); toggleRun() }}
          className={`relative flex-shrink-0 w-10 h-5 rounded-full transition-colors ${
            enabled ? 'bg-indigo-500' : 'bg-slate-300'
          } ${alwaysRuns ? 'cursor-not-allowed' : 'cursor-pointer'}`}
          title={alwaysRuns ? 'This step always runs' : enabled ? 'Click to skip this step' : 'Click to enable this step'}
        >
          <span className={`absolute top-0.5 left-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform ${enabled ? 'translate-x-5' : ''}`} />
        </div>

        <span className="font-medium text-sm flex-1">{step.label}</span>

        {alwaysRuns && <span className="text-xs text-slate-400">always runs</span>}
        {!alwaysRuns && !enabled && <span className="text-xs text-slate-400">skipped</span>}

        <svg className={`w-4 h-4 text-slate-400 transition-transform ${open ? 'rotate-180' : ''}`}
             fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
          <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
        </svg>
      </div>

      {open && step.params.length > 0 && (
        <div className={`px-5 pb-4 grid gap-3 ${step.params.length === 1 ? 'grid-cols-1' : 'grid-cols-2'}`}>
          {step.params.map((p: any) => {
            const val = String(params[p.key] ?? p.default)
            return (
              <div key={p.key}>
                <label className="block text-xs font-medium text-slate-600 mb-1">{p.label}</label>
                <ParamField p={p} value={val} onChange={(v) => setParam(p.key, v)} />
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── Pipelines catalogue tab ───────────────────────────────────────────────────
function PipelineReadme({ pipelineId }: { pipelineId: string }) {
  const { data: readme = '', isLoading } = useQuery({
    queryKey: ['pipeline-readme', pipelineId],
    queryFn: () => getPipelineReadme(pipelineId),
  })

  if (isLoading) return <p className="text-sm text-slate-400 italic">Loading description…</p>

  return (
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      components={{
        h1: ({ children }) => <h1 className="text-xl font-bold mt-6 mb-3 text-slate-900">{children}</h1>,
        h2: ({ children }) => <h2 className="text-base font-semibold mt-5 mb-2 text-slate-800 border-b border-slate-200 pb-1">{children}</h2>,
        h3: ({ children }) => <h3 className="text-sm font-semibold mt-4 mb-1 text-slate-700">{children}</h3>,
        p:  ({ children }) => <p className="text-sm text-slate-700 mb-3 leading-relaxed">{children}</p>,
        ul: ({ children }) => <ul className="list-disc list-inside text-sm text-slate-700 mb-3 space-y-1">{children}</ul>,
        ol: ({ children }) => <ol className="list-decimal list-inside text-sm text-slate-700 mb-3 space-y-1">{children}</ol>,
        li: ({ children }) => <li className="text-sm text-slate-700">{children}</li>,
        code: ({ children, className }) => className
          ? <code className="block bg-slate-100 rounded p-3 text-xs font-mono text-slate-800 overflow-x-auto mb-3 whitespace-pre">{children}</code>
          : <code className="bg-slate-100 rounded px-1 py-0.5 text-xs font-mono text-slate-800">{children}</code>,
        pre: ({ children }) => <pre className="mb-3">{children}</pre>,
        table: ({ children }) => (
          <div className="overflow-x-auto mb-4">
            <table className="min-w-full text-sm border-collapse">{children}</table>
          </div>
        ),
        thead: ({ children }) => <thead className="bg-slate-100">{children}</thead>,
        th: ({ children }) => <th className="border border-slate-300 px-3 py-1.5 text-left text-xs font-semibold text-slate-700">{children}</th>,
        td: ({ children }) => <td className="border border-slate-200 px-3 py-1.5 text-sm text-slate-700">{children}</td>,
        tr: ({ children }) => <tr className="even:bg-slate-50">{children}</tr>,
        strong: ({ children }) => <strong className="font-semibold text-slate-900">{children}</strong>,
        blockquote: ({ children }) => <blockquote className="border-l-4 border-indigo-300 pl-4 italic text-slate-600 mb-3">{children}</blockquote>,
        hr: () => <hr className="border-slate-200 my-4" />,
      }}
    >
      {readme}
    </ReactMarkdown>
  )
}

function PipelinesTab({ pipelines }: { pipelines: any[] }) {
  const [selected, setSelected] = useState<string | null>(pipelines[0]?.id ?? null)

  return (
    <div className="flex gap-6">
      {/* Sidebar list */}
      <div className="w-56 flex-shrink-0">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Available Pipelines</h3>
        <ul className="space-y-1">
          {pipelines.map((p: any) => (
            <li key={p.id}>
              <button
                onClick={() => setSelected(p.id)}
                className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors ${
                  selected === p.id
                    ? 'bg-indigo-50 text-indigo-700 font-medium'
                    : 'hover:bg-slate-100 text-slate-700'
                }`}
              >
                {p.name}
              </button>
            </li>
          ))}
        </ul>
      </div>

      {/* Content area */}
      <div className="flex-1 bg-white rounded-xl shadow p-6 min-w-0 overflow-y-auto max-h-[calc(100vh-12rem)]">
        {selected ? (
          <>
            <h2 className="text-lg font-semibold mb-4">
              {pipelines.find((p: any) => p.id === selected)?.name}
            </h2>
            <PipelineReadme pipelineId={selected} />
          </>
        ) : (
          <p className="text-slate-400 text-sm">Select a pipeline from the list.</p>
        )}
      </div>
    </div>
  )
}

// ── Submit tab ────────────────────────────────────────────────────────────────
function SubmitTab({ pipelines }: { pipelines: any[] }) {
  const navigate = useNavigate()
  const [selectedPipeline, setSelectedPipeline] = useState('basic_Seurat_single_cell_pipeline')
  const [files, setFiles] = useState<File[]>([])
  const [params, setParams] = useState<Record<string, string>>({})
  const [uploading, setUploading] = useState(false)
  const [uploadProgress, setUploadProgress] = useState(0)

  function setParam(key: string, val: string) {
    setParams((prev) => ({ ...prev, [key]: val }))
  }

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
  const currentPipeline = pipelines.find((p: any) => p.id === selectedPipeline)

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
      const defaults: Record<string, string> = {}
      if (currentPipeline?.steps) {
        for (const step of currentPipeline.steps) {
          if (step.run_key) defaults[step.run_key] = 'true'
          for (const p of step.params) {
            if (p.default !== undefined && p.default !== null) {
              defaults[p.key] = String(p.default)
            }
          }
        }
      }
      const fullParams = { ...defaults, ...params }
      const job = await submitJob(selectedPipeline, batch_id, fullParams)
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

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      {/* 1. Pipeline selector */}
      <div className="bg-white rounded-xl shadow p-5">
        <h3 className="font-medium mb-3">1. Select Pipeline</h3>
        <select
          value={selectedPipeline}
          onChange={(e) => { setSelectedPipeline(e.target.value); setParams({}) }}
          className="w-full border rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
        >
          {pipelines.map((p: any) => (
            <option key={p.id} value={p.id}>{p.name}</option>
          ))}
        </select>
        {currentPipeline && (
          <p className="mt-2 text-xs text-slate-500">{currentPipeline.description}</p>
        )}
      </div>

      {/* 2. File upload */}
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

      {/* 3. Pipeline steps */}
      {currentPipeline?.steps && (
        <div className="space-y-3">
          <h3 className="font-medium px-1">3. Pipeline Steps &amp; Parameters</h3>
          {currentPipeline.steps.map((step: any) => (
            <StepPanel key={step.key} step={step} params={params} setParam={setParam} />
          ))}
        </div>
      )}

      {uploading && (
        <div className="w-full bg-slate-200 rounded-full h-2">
          <div className="bg-indigo-500 h-2 rounded-full transition-all duration-300"
               style={{ width: `${uploadProgress}%` }} />
        </div>
      )}

      <button type="submit" disabled={uploading}
        className="w-full bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg py-2.5 font-medium disabled:opacity-50">
        {uploading ? 'Uploading & submitting…' : 'Submit Job'}
      </button>
    </form>
  )
}

// ── Main page ─────────────────────────────────────────────────────────────────
export default function SubmitJobPage() {
  const { data: pipelines = [] } = useQuery({ queryKey: ['pipelines'], queryFn: listPipelines })
  const [tab, setTab] = useState<'submit' | 'pipelines'>('submit')

  const tabs = [
    { id: 'submit',    label: 'Submit Job' },
    { id: 'pipelines', label: 'Pipelines' },
  ] as const

  return (
    <div className="max-w-4xl">
      {/* Tab bar */}
      <div className="flex gap-1 mb-6 border-b border-slate-200">
        {tabs.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={`px-4 py-2 text-sm font-medium transition-colors border-b-2 -mb-px ${
              tab === t.id
                ? 'border-indigo-600 text-indigo-700'
                : 'border-transparent text-slate-500 hover:text-slate-700'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'submit' && <SubmitTab pipelines={pipelines} />}
      {tab === 'pipelines' && <PipelinesTab pipelines={pipelines} />}
    </div>
  )
}
