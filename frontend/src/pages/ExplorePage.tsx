import { useState, useCallback, useMemo } from 'react'
import { useDropzone } from 'react-dropzone'
import { useQuery } from '@tanstack/react-query'
import Plot from 'react-plotly.js'
import toast from 'react-hot-toast'
import { uploadRds, getGeneExpression, runDGE, listPresets, loadPreset, SeuratMeta, DGEResult, PresetProject } from '../api/explore'

// ── Colour scales ──────────────────────────────────────────────────────────────
const CAT_COLORS = [
  '#6366f1','#f59e0b','#10b981','#ef4444','#3b82f6','#8b5cf6',
  '#ec4899','#14b8a6','#f97316','#84cc16','#06b6d4','#a855f7',
]

function catColorMap(vals: string[]): Record<string, string> {
  const unique = [...new Set(vals)]
  return Object.fromEntries(unique.map((v, i) => [v, CAT_COLORS[i % CAT_COLORS.length]]))
}

// ── Sub-components ─────────────────────────────────────────────────────────────
function Sidebar({
  meta, reduction, setReduction, colorBy, setColorBy,
  assay, setAssay, slot, setSlot,
  splitBy, setSplitBy,
  selectedClusters, setSelectedClusters,
}: any) {
  const meta_cols = Object.keys(meta.metadata)
  const clusterVals = useMemo(() =>
    [...new Set(meta.metadata[colorBy] ?? [])].sort(), [meta, colorBy])

  return (
    <div className="w-64 shrink-0 bg-white border-r border-slate-200 overflow-y-auto p-4 space-y-4 text-sm">
      <div>
        <div className="text-xs font-semibold text-slate-400 uppercase tracking-wide mb-1">Object</div>
        <div className="text-slate-600">{meta.n_cells.toLocaleString()} cells · {meta.n_features.toLocaleString()} genes</div>
      </div>

      <div>
        <label className="text-xs font-semibold text-slate-400 uppercase tracking-wide">Reduction</label>
        <select value={reduction} onChange={e => setReduction(e.target.value)}
          className="mt-1 w-full border border-slate-300 rounded px-2 py-1 text-sm">
          {Object.keys(meta.reductions).map(r => <option key={r}>{r}</option>)}
        </select>
      </div>

      <div>
        <label className="text-xs font-semibold text-slate-400 uppercase tracking-wide">Colour by</label>
        <select value={colorBy} onChange={e => setColorBy(e.target.value)}
          className="mt-1 w-full border border-slate-300 rounded px-2 py-1 text-sm">
          {meta_cols.map(c => <option key={c}>{c}</option>)}
        </select>
      </div>

      <div>
        <label className="text-xs font-semibold text-slate-400 uppercase tracking-wide">Assay</label>
        <select value={assay} onChange={e => setAssay(e.target.value)}
          className="mt-1 w-full border border-slate-300 rounded px-2 py-1 text-sm">
          {meta.assays.map((a: string) => <option key={a}>{a}</option>)}
        </select>
      </div>

      <div>
        <label className="text-xs font-semibold text-slate-400 uppercase tracking-wide">Data slot</label>
        <select value={slot} onChange={e => setSlot(e.target.value)}
          className="mt-1 w-full border border-slate-300 rounded px-2 py-1 text-sm">
          {['data','counts','scale.data'].map(s => <option key={s}>{s}</option>)}
        </select>
      </div>

      <div>
        <label className="text-xs font-semibold text-slate-400 uppercase tracking-wide">Split by</label>
        <select value={splitBy} onChange={e => setSplitBy(e.target.value)}
          className="mt-1 w-full border border-slate-300 rounded px-2 py-1 text-sm">
          <option value="">None</option>
          {meta_cols.map(c => <option key={c}>{c}</option>)}
        </select>
      </div>

      <div>
        <div className="text-xs font-semibold text-slate-400 uppercase tracking-wide mb-1">
          Subset clusters
          <button onClick={() => setSelectedClusters(clusterVals)}
            className="ml-2 text-indigo-500 hover:underline font-normal normal-case">all</button>
          <button onClick={() => setSelectedClusters([])}
            className="ml-1 text-indigo-500 hover:underline font-normal normal-case">none</button>
        </div>
        <div className="max-h-48 overflow-y-auto space-y-0.5">
          {clusterVals.map(v => (
            <label key={v} className="flex items-center gap-1.5 cursor-pointer hover:bg-slate-50 px-1 rounded">
              <input type="checkbox" checked={selectedClusters.includes(v)}
                onChange={e => setSelectedClusters((prev: string[]) =>
                  e.target.checked ? [...prev, v] : prev.filter(x => x !== v))} />
              <span className="truncate">{v}</span>
            </label>
          ))}
        </div>
      </div>
    </div>
  )
}

// ── UMAP plot ──────────────────────────────────────────────────────────────────
function UMAPTab({ meta, reduction, colorBy, splitBy, selectedClusters }: any) {
  const red  = meta.reductions[reduction]
  if (!red) return <p className="text-slate-400 p-8">Reduction not found.</p>

  // Build cell→metadata index so ordering is always correct regardless of reduction
  const metaIndex = useMemo(
    () => Object.fromEntries(meta.cells.map((c: string, i: number) => [c, i])),
    [meta.cells]
  )
  const allColorVals = meta.metadata[colorBy] ?? []
  // Map each cell in THIS reduction to its colorBy value
  const colorVals = red.cells.map((c: string) => allColorVals[metaIndex[c]] ?? '')
  const colorMap  = catColorMap(colorVals)

  const mask   = colorVals.map((v: string) => selectedClusters.includes(v))
  const groups = [...new Set(colorVals.filter((_: string, i: number) => mask[i]))]

  const splitValsAll = splitBy ? (meta.metadata[splitBy] ?? []) : []
  const splitMeta    = splitBy
    ? red.cells.map((c: string) => splitValsAll[metaIndex[c]] ?? '')
    : []
  const splitGroups  = splitBy ? [...new Set(splitMeta)] : [null]

  const makePlot = (grp: string | null) => {
    const traces = groups.map((g: any) => {
      const idx = red.cells
        .map((_: string, i: number) => i)
        .filter((i: number) => mask[i] && colorVals[i] === g && (!grp || splitMeta[i] === grp))
      return {
        type: 'scatter' as const,
        mode: 'markers' as const,
        name: String(g),
        x: idx.map((i: number) => red.x[i]),
        y: idx.map((i: number) => red.y[i]),
        marker: { color: colorMap[g as string], size: 6, opacity: 0.85 },
        text: idx.map((i: number) => `${red.cells[i]}<br>${colorBy}: ${g}`),
        hoverinfo: 'text' as const,
      }
    })
    return (
      <div key={grp ?? 'all'} style={{ width: 1120, flexShrink: 0 }}>
        {grp && <div className="text-center text-xs text-slate-500 mb-1">{grp}</div>}
        <Plot key={`${reduction}-${grp ?? 'all'}-${colorBy}`} data={traces} layout={{
          width: 1120, height: 1040,
          title: grp ? undefined : { text: `${reduction} — ${colorBy}`, font: { size: 13 } },
          xaxis: { title: `${reduction}_1`, showgrid: false, zeroline: false, constrain: 'domain' },
          yaxis: { title: `${reduction}_2`, showgrid: false, zeroline: false, scaleanchor: 'x', scaleratio: 1 },
          legend: { itemsizing: 'constant' },
          margin: { t: 40, l: 55, r: 20, b: 55 },
          paper_bgcolor: 'transparent', plot_bgcolor: 'transparent',
        }} config={{ responsive: false }} />
      </div>
    )
  }

  return (
    <div className="p-4">
      <div className="flex flex-wrap gap-2">{splitGroups.map(makePlot)}</div>
    </div>
  )
}

// ── Feature plot ───────────────────────────────────────────────────────────────
function FeaturePlotTab({ meta, reduction, assay, slot, selectedClusters, colorBy, sessionId }: any) {
  const [geneInput, setGeneInput] = useState('')
  const [exprData,  setExprData]  = useState<Record<string, number[]> | null>(null)
  const [cells,     setCells]     = useState<string[]>([])
  const [loading,   setLoading]   = useState(false)

  const genes = geneInput.split(',').map((g: string) => g.trim()).filter(Boolean)
  const red   = meta.reductions[reduction]

  async function fetchExpr() {
    if (!genes.length) { toast.error('Enter at least one gene'); return }
    setLoading(true)
    try {
      const res = await getGeneExpression(sessionId, genes.join(','), assay, slot)
      setExprData(res.expression)
      setCells(res.cells)
    } catch (e: any) { toast.error(e.response?.data?.detail || 'Failed to fetch expression') }
    finally { setLoading(false) }
  }

  function clearResults() { setExprData(null); setCells([]); setGeneInput('') }

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center gap-3">
        <input value={geneInput} onChange={e => setGeneInput(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && fetchExpr()}
          placeholder="Gene(s) — comma separated, e.g. Cd3e, Cd8a"
          className="border border-slate-300 rounded-lg px-3 py-2 text-sm w-96 focus:outline-none focus:ring-2 focus:ring-indigo-400" />
        <button onClick={fetchExpr} disabled={loading}
          className="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-lg text-sm disabled:opacity-50">
          {loading ? 'Loading…' : 'Plot'}
        </button>
        {exprData && (
          <button onClick={clearResults}
            className="text-sm text-slate-400 hover:text-red-500 border border-slate-200 hover:border-red-300 px-3 py-2 rounded-lg transition-colors">
            Clear
          </button>
        )}
      </div>

      {exprData && red && (
        <div className="flex flex-wrap gap-4">
          {genes.filter(g => exprData[g]).map(gene => {
            const exprVals = exprData[gene]
            const idxMap   = Object.fromEntries(cells.map((c, i) => [c, i]))
            const traces = [{
              type: 'scatter' as const,
              mode: 'markers' as const,
              x: red.cells.map((c: string) => red.x[red.cells.indexOf(c)]),
              y: red.cells.map((c: string) => red.y[red.cells.indexOf(c)]),
              marker: {
                color: red.cells.map((c: string) => exprVals[idxMap[c]] ?? 0),
                colorscale: [[0, '#d3d3d3'], [0.05, '#c6dbef'], [0.2, '#6baed6'], [0.5, '#2171b5'], [1, '#08306b']],
                size: 6, opacity: 0.85,
                showscale: true, colorbar: { thickness: 12, len: 0.6 },
              },
              text: red.cells.map((c: string, i: number) =>
                `${c}<br>${gene}: ${(exprVals[idxMap[c]] ?? 0).toFixed(3)}`),
              hoverinfo: 'text' as const,
              name: gene,
            }]
            return (
              <div key={gene} style={{ width: 1120, flexShrink: 0 }}>
                <Plot key={`fp-${gene}-${reduction}`} data={traces} layout={{
                  width: 1120, height: 1040,
                  title: { text: gene, font: { size: 14 } },
                  xaxis: { title: `${reduction}_1`, showgrid: false, zeroline: false, constrain: 'domain' },
                  yaxis: { title: `${reduction}_2`, showgrid: false, zeroline: false, scaleanchor: 'x', scaleratio: 1 },
                  margin: { t: 50, l: 55, r: 20, b: 55 },
                  paper_bgcolor: 'transparent', plot_bgcolor: 'transparent',
                }} config={{ responsive: false }} />
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── Violin plot ────────────────────────────────────────────────────────────────
function ViolinTab({ meta, assay, slot, selectedClusters, colorBy, sessionId }: any) {
  const [geneInput, setGeneInput] = useState('')
  const [exprData,  setExprData]  = useState<Record<string, number[]> | null>(null)
  const [cells,     setCells]     = useState<string[]>([])
  const [loading,   setLoading]   = useState(false)

  const genes     = geneInput.split(',').map((g: string) => g.trim()).filter(Boolean)
  const colorVals = meta.metadata[colorBy] ?? []
  const colorMap  = catColorMap(colorVals)
  const groups    = [...new Set(colorVals)].filter((g: string) => selectedClusters.includes(g)).sort()

  async function fetchExpr() {
    if (!genes.length) { toast.error('Enter at least one gene'); return }
    setLoading(true)
    try {
      const res = await getGeneExpression(sessionId, genes.join(','), assay, slot)
      setExprData(res.expression)
      setCells(res.cells)
    } catch (e: any) { toast.error(e.response?.data?.detail || 'Failed') }
    finally { setLoading(false) }
  }

  function clearResults() { setExprData(null); setCells([]); setGeneInput('') }

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center gap-3">
        <input value={geneInput} onChange={e => setGeneInput(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && fetchExpr()}
          placeholder="Gene(s) — comma separated, e.g. Cd3e, Cd8a"
          className="border border-slate-300 rounded-lg px-3 py-2 text-sm w-96 focus:outline-none focus:ring-2 focus:ring-indigo-400" />
        <button onClick={fetchExpr} disabled={loading}
          className="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded-lg text-sm disabled:opacity-50">
          {loading ? 'Loading…' : 'Plot'}
        </button>
        {exprData && (
          <button onClick={clearResults}
            className="text-sm text-slate-400 hover:text-red-500 border border-slate-200 hover:border-red-300 px-3 py-2 rounded-lg transition-colors">
            Clear
          </button>
        )}
      </div>

      {exprData && (
        <div className="space-y-6">
          {genes.filter(g => exprData[g]).map(gene => {
            const idxMap = Object.fromEntries(cells.map((c, i) => [c, i]))
            const traces = groups.map(grp => ({
              type: 'violin' as const,
              name: String(grp),
              y: meta.cells
                .filter((_: string, i: number) => colorVals[i] === grp)
                .map((c: string) => exprData[gene][idxMap[c]] ?? 0),
              box: { visible: true },
              meanline: { visible: true },
              marker: { color: colorMap[grp as string] },
              points: false,
            }))
            return (
              <div key={gene}>
                <Plot data={traces} layout={{
                  height: 420, autosize: true,
                  title: { text: gene, font: { size: 13 } },
                  yaxis: { title: 'Expression', zeroline: false },
                  violinmode: 'group',
                  margin: { t: 40, l: 60, r: 20, b: 60 },
                  paper_bgcolor: 'transparent', plot_bgcolor: 'transparent',
                }} useResizeHandler style={{ width: '100%' }} config={{ responsive: true }} />
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── DGE ───────────────────────────────────────────────────────────────────────
function DGETab({ meta, assay, slot, colorBy, sessionId, mode }: any) {
  const [test,    setTest]    = useState('wilcox')
  const [ident1,  setIdent1]  = useState('')
  const [ident2,  setIdent2]  = useState('')
  const [rmTCR,   setRmTCR]   = useState(true)
  const [rmBCR,   setRmBCR]   = useState(true)
  const [pval,    setPval]    = useState(0.05)
  const [logfc,   setLogfc]   = useState(0.25)
  const [dgeResult, setDgeResult] = useState<DGEResult | null>(null)
  const [loading,   setLoading]   = useState(false)
  const [log,       setLog]       = useState('')
  const [showExcluded, setShowExcluded] = useState(false)

  const results = dgeResult?.markers ?? []

  const groupVals = useMemo(() => [...new Set(meta.metadata[colorBy] ?? [])].sort(), [meta, colorBy])

  async function runAnalysis() {
    setLoading(true); setLog('Running…'); setDgeResult(null)
    try {
      const res = await runDGE({
        session_id: sessionId, mode, group_by: colorBy,
        assay, slot, test_use: test,
        ident1: ident1 || undefined, ident2: ident2 || undefined,
        rm_tcr: rmTCR, rm_bcr: rmBCR,
      })
      const filtered = res.markers.filter((r: any) =>
        r.p_val_adj <= pval && Math.abs(Number(r.avg_log2FC)) >= logfc)
      setDgeResult({ ...res, markers: filtered })
      setLog(`Done — ${filtered.length} significant DEGs (${res.species} detected). TCR excluded: ${res.excluded_tcr.length}, BCR/Ig excluded: ${res.excluded_bcr.length}.`)
    } catch (e: any) { setLog('Error: ' + (e.response?.data?.detail || e.message)) }
    finally { setLoading(false) }
  }

  const clusters    = useMemo(() => [...new Set(results.map((r: any) => r.cluster))].sort(), [results])
  const [activeTab, setActiveTab] = useState<string>('')

  // auto-select first tab when results arrive
  useMemo(() => { if (clusters.length > 0) setActiveTab(String(clusters[0])) }, [clusters])

  const logfcNote = mode === 'clusters'
    ? 'avg_log2FC > 0: higher in this cluster vs all others. avg_log2FC < 0: lower in this cluster.'
    : 'avg_log2FC > 0: higher in Group 1 vs Group 2. avg_log2FC < 0: lower in Group 1.'

  const DGE_COLS = ['gene','p_val','p_val_adj','avg_log2FC','pct.1','pct.2']

  function downloadCSV(rows: any[], filename: string) {
    const header = DGE_COLS.join(',')
    const body   = rows.map(r => DGE_COLS.map(c => JSON.stringify(r[c] ?? '')).join(',')).join('\n')
    const blob   = new Blob([`${header}\n${body}`], { type: 'text/csv' })
    const a      = Object.assign(document.createElement('a'), { href: URL.createObjectURL(blob), download: filename })
    a.click(); URL.revokeObjectURL(a.href)
  }

  return (
    <div className="p-4 space-y-4">
      {/* Controls */}
      <div className="bg-slate-50 rounded-lg p-4 space-y-3">
        <div className="flex flex-wrap gap-4 items-end">
          <div>
            <label className="text-xs text-slate-500 block mb-1">Test</label>
            <select value={test} onChange={e => setTest(e.target.value)}
              className="border border-slate-300 rounded px-2 py-1 text-sm">
              {['wilcox','t','MAST','DESeq2'].map(t => <option key={t}>{t}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs text-slate-500 block mb-1">adj. p-val ≤</label>
            <input type="number" value={pval} step={0.01} min={0} max={1}
              onChange={e => setPval(Number(e.target.value))}
              className="border border-slate-300 rounded px-2 py-1 text-sm w-24" />
          </div>
          <div>
            <label className="text-xs text-slate-500 block mb-1">|log2FC| ≥</label>
            <input type="number" value={logfc} step={0.05} min={0}
              onChange={e => setLogfc(Number(e.target.value))}
              className="border border-slate-300 rounded px-2 py-1 text-sm w-24" />
          </div>
          {mode === 'conditions' && (
            <>
              <div>
                <label className="text-xs text-slate-500 block mb-1">Group 1</label>
                <select value={ident1} onChange={e => setIdent1(e.target.value)}
                  className="border border-slate-300 rounded px-2 py-1 text-sm">
                  <option value="">—</option>
                  {groupVals.map(v => <option key={String(v)}>{String(v)}</option>)}
                </select>
              </div>
              <div>
                <label className="text-xs text-slate-500 block mb-1">Group 2</label>
                <select value={ident2} onChange={e => setIdent2(e.target.value)}
                  className="border border-slate-300 rounded px-2 py-1 text-sm">
                  <option value="">— (all others)</option>
                  {groupVals.map(v => <option key={String(v)}>{String(v)}</option>)}
                </select>
              </div>
            </>
          )}
          <div className="flex gap-4 items-center text-sm">
            <label className="flex items-center gap-1.5 cursor-pointer">
              <input type="checkbox" checked={rmTCR} onChange={e => setRmTCR(e.target.checked)} />
              <span>Remove TCR genes</span>
            </label>
            <label className="flex items-center gap-1.5 cursor-pointer">
              <input type="checkbox" checked={rmBCR} onChange={e => setRmBCR(e.target.checked)} />
              <span>Remove BCR/Ig genes</span>
            </label>
          </div>
          <button onClick={runAnalysis} disabled={loading}
            className="bg-indigo-600 hover:bg-indigo-700 text-white px-4 py-2 rounded text-sm disabled:opacity-50">
            {loading ? 'Running…' : mode === 'clusters' ? 'FindAllMarkers' : 'FindMarkers'}
          </button>
          {dgeResult && (
            <button onClick={() => { setDgeResult(null); setLog('') }}
              className="text-sm text-slate-400 hover:text-red-500 border border-slate-200 hover:border-red-300 px-3 py-2 rounded transition-colors">
              Clear
            </button>
          )}
        </div>
        {log && <p className="text-xs text-slate-500 font-mono">{log}</p>}
        <p className="text-xs text-slate-400 italic">ℹ {logfcNote}</p>
      </div>

      {/* Tabset results */}
      {/* Excluded genes table */}
      {dgeResult && (rmTCR || rmBCR) && (dgeResult.excluded_tcr.length > 0 || dgeResult.excluded_bcr.length > 0) && (
        <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
          <button onClick={() => setShowExcluded(v => !v)}
            className="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-slate-700 hover:bg-slate-50">
            <span>
              Excluded genes
              {rmTCR && <span className="ml-2 px-2 py-0.5 bg-purple-100 text-purple-700 rounded-full text-xs">TCR: {dgeResult.excluded_tcr.length}</span>}
              {rmBCR && <span className="ml-2 px-2 py-0.5 bg-blue-100 text-blue-700 rounded-full text-xs">BCR/Ig: {dgeResult.excluded_bcr.length}</span>}
              <span className="ml-2 text-xs text-slate-400">({dgeResult.species})</span>
            </span>
            <span className="text-slate-400">{showExcluded ? '▲' : '▼'}</span>
          </button>
          {showExcluded && (
            <div className="border-t border-slate-200 p-4">
              <div className="flex gap-6">
                {rmTCR && dgeResult.excluded_tcr.length > 0 && (
                  <div className="flex-1">
                    <div className="text-xs font-semibold text-purple-700 mb-2">TCR genes ({dgeResult.excluded_tcr.length})</div>
                    <div className="max-h-48 overflow-y-auto rounded border border-slate-100">
                      <table className="w-full text-xs">
                        <thead className="bg-slate-50 border-b sticky top-0">
                          <tr><th className="text-left px-3 py-1.5 font-medium">Gene</th></tr>
                        </thead>
                        <tbody className="divide-y">
                          {dgeResult.excluded_tcr.map(g => (
                            <tr key={g} className="hover:bg-slate-50">
                              <td className="px-3 py-1 font-mono">{g}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}
                {rmBCR && dgeResult.excluded_bcr.length > 0 && (
                  <div className="flex-1">
                    <div className="text-xs font-semibold text-blue-700 mb-2">BCR/Ig genes ({dgeResult.excluded_bcr.length})</div>
                    <div className="max-h-48 overflow-y-auto rounded border border-slate-100">
                      <table className="w-full text-xs">
                        <thead className="bg-slate-50 border-b sticky top-0">
                          <tr><th className="text-left px-3 py-1.5 font-medium">Gene</th></tr>
                        </thead>
                        <tbody className="divide-y">
                          {dgeResult.excluded_bcr.map(g => (
                            <tr key={g} className="hover:bg-slate-50">
                              <td className="px-3 py-1 font-mono">{g}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {results.length > 0 && mode === 'conditions' && (() => {
        const allRows = results.filter((r: any) => r.avg_log2FC != null && r.p_val != null)

        // use p_val_adj; fall back to p_val when p_val_adj === 0
        const negLog10 = (r: any) => {
          const p = (Number(r.p_val_adj) === 0 || r.p_val_adj == null)
            ? Number(r.p_val)
            : Number(r.p_val_adj)
          return -Math.log10(p || 1e-300)
        }

        const sorted    = [...allRows].sort((a: any, b: any) => Number(b.avg_log2FC) - Number(a.avg_log2FC))
        const top10up   = sorted.slice(0, 10)
        const top10down = [...sorted].reverse().slice(0, 10)

        const x      = allRows.map((r: any) => Number(r.avg_log2FC))
        const y      = allRows.map(negLog10)
        const colors = allRows.map((r: any) => Number(r.avg_log2FC) > 0 ? '#e15759' : '#4e79a7')
        const hover  = allRows.map((r: any) =>
          `<b>${r.gene}</b><br>log2FC: ${Number(r.avg_log2FC).toFixed(3)}<br>-log10(p): ${negLog10(r).toFixed(2)}<extra></extra>`)

        // build annotations with staggered offsets (repel-like)
        const makeAnnotations = (genes: any[], side: 'right' | 'left') => {
          const xSign = side === 'right' ? 1 : -1
          return genes.map((r: any, i: number) => ({
            x: Number(r.avg_log2FC),
            y: negLog10(r),
            text: `<b>${r.gene}</b>`,
            showarrow: true,
            arrowhead: 2,
            arrowsize: 0.8,
            arrowwidth: 1,
            arrowcolor: '#999',
            ax: xSign * (38 + (i % 3) * 14),
            ay: -20 - (i % 5) * 12,
            font: { size: 10, color: side === 'right' ? '#c0392b' : '#2c6fad' },
            bgcolor: 'rgba(255,255,255,0.85)',
            borderpad: 2,
            xanchor: side,
          }))
        }

        const annotations = [
          ...makeAnnotations(top10up, 'right'),
          ...makeAnnotations(top10down, 'left'),
        ]

        return (
          <div className="bg-white rounded-lg border border-slate-200 p-4 flex flex-col items-center">
            <h4 className="text-sm font-medium text-slate-700 mb-2">Volcano Plot</h4>
            <Plot
              data={[{
                type: 'scatter', mode: 'markers',
                x, y,
                marker: { color: colors, size: 6, opacity: 0.7 },
                hovertemplate: hover,
              }]}
              layout={{
                height: 750,
                width: 560,
                margin: { t: 20, r: 100, b: 50, l: 70 },
                xaxis: { title: { text: 'avg_log2FC' }, zeroline: true, zerolinecolor: '#aaa', zerolinewidth: 1 },
                yaxis: { title: { text: '-log10(p)' } },
                annotations,
                shapes: [{ type: 'line', x0: 0, x1: 0, y0: 0, y1: 1, xref: 'x', yref: 'paper', line: { color: '#aaa', width: 1, dash: 'dash' } }],
                paper_bgcolor: 'transparent', plot_bgcolor: 'transparent',
                font: { size: 11 },
                showlegend: false,
              }}
              config={{ displayModeBar: false }}
            />
            <p className="text-xs text-slate-400 mt-1">
              Red = up in Group 1 · Blue = down · Labels: top 10 up + top 10 down by log2FC · y-axis uses p_val when p_val_adj = 0
            </p>
          </div>
        )
      })()}

      {results.length > 0 && (
        <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
          {/* Tab strip */}
          <div className="flex overflow-x-auto border-b border-slate-200 bg-slate-50">
            {clusters.map(cl => {
              const n = results.filter((r: any) => r.cluster === cl).length
              return (
                <button key={String(cl)}
                  onClick={() => setActiveTab(String(cl))}
                  className={`px-4 py-2.5 text-xs font-medium whitespace-nowrap border-b-2 transition-colors
                    ${activeTab === String(cl)
                      ? 'border-indigo-600 text-indigo-600 bg-white'
                      : 'border-transparent text-slate-500 hover:text-slate-700 hover:bg-white'}`}>
                  {mode === 'clusters' ? `Cluster ${cl}` : String(cl)}
                  <span className="ml-1.5 text-slate-400">({n})</span>
                </button>
              )
            })}
            {/* Download all */}
            <div className="ml-auto px-3 flex items-center">
              <button onClick={() => downloadCSV(results, `dge_all.csv`)}
                className="text-xs text-slate-400 hover:text-indigo-600">⬇ All CSV</button>
            </div>
          </div>

          {/* Active cluster table */}
          {clusters.filter(cl => String(cl) === activeTab).map(cl => {
            const clRows = results
              .filter((r: any) => r.cluster === cl)
              .sort((a: any, b: any) => Math.abs(Number(b.avg_log2FC)) - Math.abs(Number(a.avg_log2FC)))
            return (
              <div key={String(cl)}>
                <div className="flex items-center justify-between px-4 py-2 border-b bg-slate-50 text-xs text-slate-500">
                  <span>{clRows.length} significant DEGs</span>
                  <button onClick={() => downloadCSV(clRows, `dge_cluster_${cl}.csv`)}
                    className="text-indigo-500 hover:underline">⬇ Download CSV</button>
                </div>
                <div className="overflow-auto max-h-[55vh]">
                  <table className="w-full text-xs">
                    <thead className="bg-slate-50 border-b sticky top-0">
                      <tr>
                        <th className="text-left px-3 py-2 font-medium">Gene</th>
                        <th className="text-left px-3 py-2 font-medium">p_val</th>
                        <th className="text-left px-3 py-2 font-medium">p_val_adj</th>
                        <th className="text-left px-3 py-2 font-medium">avg_log2FC</th>
                        <th className="text-left px-3 py-2 font-medium">pct.1</th>
                        <th className="text-left px-3 py-2 font-medium">pct.2</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y">
                      {clRows.map((r: any, i: number) => (
                        <tr key={i} className="hover:bg-slate-50">
                          <td className="px-3 py-1.5 font-semibold">{String(r.gene)}</td>
                          <td className="px-3 py-1.5 text-slate-500 font-mono">{Number(r.p_val).toExponential(2)}</td>
                          <td className="px-3 py-1.5 text-slate-500 font-mono">{Number(r.p_val_adj).toExponential(2)}</td>
                          <td className={`px-3 py-1.5 font-mono font-medium ${Number(r.avg_log2FC) > 0 ? 'text-green-600' : 'text-red-500'}`}>
                            {Number(r.avg_log2FC) > 0 ? '+' : ''}{Number(r.avg_log2FC).toFixed(3)}
                          </td>
                          <td className="px-3 py-1.5 text-slate-500">{Number(r['pct.1']).toFixed(2)}</td>
                          <td className="px-3 py-1.5 text-slate-500">{Number(r['pct.2']).toFixed(2)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── Metadata table ─────────────────────────────────────────────────────────────
function MetadataTab({ meta }: { meta: SeuratMeta }) {
  const cols = Object.keys(meta.metadata)
  const rows = meta.cells.map((cell, i) =>
    Object.fromEntries([['cell', cell], ...cols.map(c => [c, meta.metadata[c]?.[i] ?? ''])]))
  const [filter, setFilter] = useState('')
  const visible = filter ? rows.filter(r =>
    Object.values(r).some(v => String(v).toLowerCase().includes(filter.toLowerCase()))
  ) : rows

  return (
    <div className="p-4 space-y-3">
      <input value={filter} onChange={e => setFilter(e.target.value)}
        placeholder="Filter cells…"
        className="border border-slate-300 rounded px-3 py-1.5 text-sm w-64" />
      <p className="text-xs text-slate-400">Showing {Math.min(visible.length, 500)} of {visible.length} cells</p>
      <div className="overflow-auto rounded-lg border border-slate-200 max-h-[60vh]">
        <table className="text-xs w-full">
          <thead className="bg-slate-50 border-b sticky top-0">
            <tr>
              {['cell', ...cols].map(c => (
                <th key={c} className="text-left px-3 py-2 font-medium whitespace-nowrap">{c}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y">
            {visible.slice(0, 500).map((row, i) => (
              <tr key={i} className="hover:bg-slate-50">
                {['cell', ...cols].map(c => (
                  <td key={c} className="px-3 py-1.5 whitespace-nowrap text-slate-600 max-w-xs truncate">
                    {String(row[c])}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

// ── Upload screen ──────────────────────────────────────────────────────────────
function UploadScreen({ onLoad }: { onLoad: (m: SeuratMeta) => void }) {
  const [loading, setLoading] = useState(false)
  const [loadingPreset, setLoadingPreset] = useState<string | null>(null)

  const { data: presets = [] } = useQuery({
    queryKey: ['explore-presets'],
    queryFn: listPresets,
  })
  const [selectedProject, setSelectedProject] = useState<string>('')
  const [selectedFile, setSelectedFile] = useState<string>('')

  const onDrop = useCallback(async (files: File[]) => {
    if (!files[0]) return
    setLoading(true)
    const tid = toast.loading('Reading Seurat object… this may take a minute')
    try {
      const meta = await uploadRds(files[0])
      toast.success('Object loaded!', { id: tid })
      onLoad(meta)
    } catch (e: any) {
      toast.error(e.response?.data?.detail || 'Upload failed', { id: tid })
    } finally { setLoading(false) }
  }, [onLoad])

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop, accept: { 'application/octet-stream': ['.rds'] }, multiple: false, disabled: loading,
  })

  async function handleLoadPreset(project: string, filename: string) {
    setLoadingPreset(filename)
    const tid = toast.loading('Loading preset… this may take a minute')
    try {
      const meta = await loadPreset(project, filename)
      toast.success('Object loaded!', { id: tid })
      onLoad(meta)
    } catch (e: any) {
      toast.error(e.response?.data?.detail || 'Failed to load preset', { id: tid })
    } finally { setLoadingPreset(null) }
  }

  const anyLoading = loading || loadingPreset !== null

  return (
    <div className="flex items-center justify-center h-full min-h-[60vh]">
      <div className="space-y-6 w-full max-w-xl">
        <div className="text-center">
          <h2 className="text-2xl font-semibold text-slate-700">Interactive Explorer</h2>
          <p className="text-slate-400 mt-2">Upload a Seurat .rds file or load a saved preset</p>
        </div>

        {/* Drop zone */}
        <div {...getRootProps()} className={`border-2 border-dashed rounded-xl p-10 text-center cursor-pointer transition-colors
          ${isDragActive ? 'border-indigo-400 bg-indigo-50' : 'border-slate-300 hover:border-indigo-300 hover:bg-slate-50'}
          ${anyLoading ? 'opacity-50 pointer-events-none' : ''}`}>
          <input {...getInputProps()} />
          <div className="text-slate-400 space-y-2">
            <div className="text-4xl">📂</div>
            <p className="font-medium">{isDragActive ? 'Drop it here' : 'Drag & drop a .rds file'}</p>
            <p className="text-sm">or click to browse</p>
          </div>
        </div>

        {loading && <p className="text-sm text-center text-slate-400 animate-pulse">Extracting object metadata…</p>}

        {/* Presets */}
        {presets.length > 0 && (
          <div>
            <div className="flex items-center gap-3 mb-3">
              <div className="flex-1 h-px bg-slate-200" />
              <span className="text-xs text-slate-400 font-medium uppercase tracking-wide">or load a saved preset</span>
              <div className="flex-1 h-px bg-slate-200" />
            </div>

            {/* Project dropdown */}
            <select
              value={selectedProject}
              onChange={(e) => { setSelectedProject(e.target.value); setSelectedFile('') }}
              disabled={anyLoading}
              className="w-full border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400 bg-white mb-3 disabled:opacity-50"
            >
              <option value="">— Select a project —</option>
              {presets.map((proj) => (
                <option key={proj.project} value={proj.project}>
                  📁 {proj.project} ({proj.files.length} file{proj.files.length !== 1 ? 's' : ''})
                </option>
              ))}
            </select>

            {/* File dropdown for selected project */}
            {selectedProject && (() => {
              const proj = presets.find((p) => p.project === selectedProject)
              if (!proj) return null
              const file = proj.files.find((f) => f.filename === selectedFile)
              return (
                <div className="flex gap-2">
                  <select
                    value={selectedFile}
                    onChange={(e) => setSelectedFile(e.target.value)}
                    disabled={anyLoading}
                    className="flex-1 border border-slate-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400 bg-white disabled:opacity-50"
                  >
                    <option value="">— Select a file —</option>
                    {proj.files.map((f) => (
                      <option key={f.filename} value={f.filename}>
                        {f.name} ({f.size_mb} MB)
                      </option>
                    ))}
                  </select>
                  <button
                    disabled={!selectedFile || anyLoading}
                    onClick={() => file && handleLoadPreset(proj.project, file.filename)}
                    className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-medium rounded-lg disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                  >
                    {loadingPreset ? 'Loading…' : 'Load'}
                  </button>
                </div>
              )
            })()}
          </div>
        )}

        {presets.length === 0 && (
          <p className="text-xs text-center text-slate-400">
            Place .rds files in <code className="bg-slate-100 px-1 rounded">data/explore/presets/&lt;project&gt;/</code> to enable quick-load.
          </p>
        )}
      </div>
    </div>
  )
}

// ── Main page ──────────────────────────────────────────────────────────────────
const TABS = ['UMAP', 'Feature Plot', 'Violin Plot', 'DGE — Clusters', 'DGE — Conditions', 'Metadata']

export default function ExplorePage() {
  const [meta,     setMeta]     = useState<SeuratMeta | null>(null)
  const [tab,      setTab]      = useState('UMAP')
  const [reduction, setReduction] = useState('')
  const [colorBy,  setColorBy]  = useState('')
  const [assay,    setAssay]    = useState('RNA')
  const [slot,     setSlot]     = useState('data')
  const [splitBy,  setSplitBy]  = useState('')
  const [selectedClusters, setSelectedClusters] = useState<string[]>([])

  function handleLoad(m: SeuratMeta) {
    setMeta(m)
    const reds = Object.keys(m.reductions)
    setReduction(reds.find(r => r.includes('umap')) ?? reds[0] ?? '')
    const cols = Object.keys(m.metadata)
    setColorBy(cols.find(c => c === 'seurat_clusters') ?? cols[0] ?? '')
    setAssay(m.assays.find(a => a === 'RNA') ?? m.assays[0] ?? 'RNA')
    const clVals = [...new Set(Object.values(m.metadata)[0] ?? [])]
    setSelectedClusters(clVals as string[])
  }

  if (!meta) return <UploadScreen onLoad={handleLoad} />

  // update cluster list when colorBy changes
  const clusterVals = [...new Set(meta.metadata[colorBy] ?? [])].sort()

  return (
    <div className="flex h-full">
      <Sidebar
        meta={meta} reduction={reduction} setReduction={setReduction}
        colorBy={colorBy} setColorBy={(v: string) => {
          setColorBy(v)
          setSelectedClusters([...new Set(meta.metadata[v] ?? [])] as string[])
        }}
        assay={assay} setAssay={setAssay} slot={slot} setSlot={setSlot}
        splitBy={splitBy} setSplitBy={setSplitBy}
        selectedClusters={selectedClusters} setSelectedClusters={setSelectedClusters}
      />

      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Tab bar */}
        <div className="flex border-b border-slate-200 bg-white px-4 gap-1 shrink-0">
          {TABS.map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={`px-4 py-3 text-sm font-medium border-b-2 transition-colors whitespace-nowrap
                ${tab === t ? 'border-indigo-600 text-indigo-600' : 'border-transparent text-slate-500 hover:text-slate-700'}`}>
              {t}
            </button>
          ))}
          <div className="ml-auto flex items-center">
            <button onClick={() => { setMeta(null); setTab('UMAP') }}
              className="text-xs text-slate-400 hover:text-slate-600 px-3">
              ↩ Load new file
            </button>
          </div>
        </div>

        {/* Tab content — all tabs stay mounted to preserve state; inactive ones are hidden */}
        <div className="flex-1 overflow-auto bg-slate-50">
          <div className={tab === 'UMAP' ? '' : 'hidden'}>
            <UMAPTab meta={meta} reduction={reduction} colorBy={colorBy}
              splitBy={splitBy} selectedClusters={selectedClusters} />
          </div>
          <div className={tab === 'Feature Plot' ? '' : 'hidden'}>
            <FeaturePlotTab meta={meta} reduction={reduction}
              assay={assay} slot={slot} selectedClusters={selectedClusters}
              colorBy={colorBy} sessionId={meta.session_id} />
          </div>
          <div className={tab === 'Violin Plot' ? '' : 'hidden'}>
            <ViolinTab meta={meta} assay={assay} slot={slot}
              selectedClusters={selectedClusters} colorBy={colorBy} sessionId={meta.session_id} />
          </div>
          <div className={tab === 'DGE — Clusters' ? '' : 'hidden'}>
            <DGETab meta={meta} assay={assay} slot={slot} colorBy={colorBy}
              sessionId={meta.session_id} mode="clusters" />
          </div>
          <div className={tab === 'DGE — Conditions' ? '' : 'hidden'}>
            <DGETab meta={meta} assay={assay} slot={slot} colorBy={colorBy}
              sessionId={meta.session_id} mode="conditions" />
          </div>
          <div className={tab === 'Metadata' ? '' : 'hidden'}>
            <MetadataTab meta={meta} />
          </div>
        </div>
      </div>
    </div>
  )
}
