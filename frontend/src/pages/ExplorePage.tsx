import { useState, useCallback, useMemo, useEffect, useRef } from 'react'
import { useDropzone } from 'react-dropzone'
import { useQuery } from '@tanstack/react-query'
import Plot from 'react-plotly.js'
import toast from 'react-hot-toast'
import { uploadRds, getGeneExpression, runDGE, listDgeCache, loadDgeCacheEntry, deleteDgeCacheEntry, listPresets, loadPreset, startPathwayAnalysis, getPathwayResult, cancelPathwayAnalysis, startCellChat, getCellChatStatus, cancelCellChat, getCacheStatus, startCacheBuild, SeuratMeta, DGEResult, DgeCacheEntry, PresetProject } from '../api/explore'

// ── Colour scales ──────────────────────────────────────────────────────────────
const CAT_COLORS = [
  '#6366f1','#f59e0b','#10b981','#ef4444','#3b82f6','#8b5cf6',
  '#ec4899','#14b8a6','#f97316','#84cc16','#06b6d4','#a855f7',
]

function catColorMap(vals: string[]): Record<string, string> {
  const unique = [...new Set(vals)]
  return Object.fromEntries(unique.map((v, i) => [v, CAT_COLORS[i % CAT_COLORS.length]]))
}

// ── Cache build button (Feature Plot / Violin Plot) ─────────────────────────
function useCacheBuild(sessionId: string, assay: string, slot: string) {
  const [building, setBuilding] = useState(false)
  const [message,  setMessage]  = useState<string | null>(null)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  // Stale "ready"/"exists" messages must not survive a change of target pair —
  // otherwise switching assay/slot after a successful cache leaves a misleading
  // "already cached" message on screen for a pair that was never built.
  useEffect(() => {
    setBuilding(false)
    setMessage(null)
    return () => {
      if (pollRef.current) clearInterval(pollRef.current)
      pollRef.current = null
    }
  }, [sessionId, assay, slot])

  async function start() {
    setMessage(null)
    try {
      const res = await startCacheBuild(sessionId, assay, slot)
      if (res.status === 'exists') {
        setMessage(res.message)
        toast(res.message, { icon: 'ℹ️' })
        return
      }
      // 'started' (we kicked it off) or 'building' (someone else already did) — wait for it either way
      setBuilding(true)
      toast(res.message, { icon: '⏳' })
      if (pollRef.current) clearInterval(pollRef.current)
      pollRef.current = setInterval(async () => {
        try {
          const s = await getCacheStatus(sessionId, assay, slot)
          if (s.status === 'ready') {
            clearInterval(pollRef.current!)
            pollRef.current = null
            setBuilding(false)
            const msg = `Cache for ${assay}/${slot} is ready.`
            setMessage(msg)
            toast.success(msg)
          }
        } catch {
          clearInterval(pollRef.current!)
          pollRef.current = null
          setBuilding(false)
        }
      }, 5000)
    } catch (e: any) {
      setBuilding(false)
      const msg = e.response?.data?.detail || 'Failed to start cache build'
      setMessage(msg)
      toast.error(msg)
    }
  }

  return { building, message, start }
}

function CacheBuildButton({ sessionId, assay, slot }: { sessionId: string; assay: string; slot: string }) {
  const { building, message, start } = useCacheBuild(sessionId, assay, slot)
  return (
    <>
      <button onClick={start} disabled={building}
        title={`Pre-compute and cache expression data for assay "${assay}", slot "${slot}"`}
        className="text-sm text-indigo-600 border border-indigo-200 hover:bg-indigo-50 px-3 py-2 rounded-lg disabled:opacity-50 whitespace-nowrap">
        {building ? 'Caching…' : `Cache ${assay}/${slot}`}
      </button>
      {message && <span className="text-xs text-slate-500">{message}</span>}
    </>
  )
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
        <select value={assay} onChange={e => {
          const newAssay = e.target.value
          setAssay(newAssay)
          const raw = meta.assay_slots?.[newAssay]
          const available: string[] = Array.isArray(raw) ? raw : raw ? [raw as string] : []
          if (available.length > 0 && !available.includes(slot)) setSlot(available[0])
        }}
          className="mt-1 w-full border border-slate-300 rounded px-2 py-1 text-sm">
          {meta.assays.map((a: string) => <option key={a}>{a}</option>)}
        </select>
      </div>

      <div>
        <label className="text-xs font-semibold text-slate-400 uppercase tracking-wide">Data slot</label>
        <select value={slot} onChange={e => setSlot(e.target.value)}
          className="mt-1 w-full border border-slate-300 rounded px-2 py-1 text-sm">
          {(() => {
            const raw = meta.assay_slots?.[assay]
            const slots: string[] = Array.isArray(raw) ? raw : raw ? [raw as string] : ['data', 'counts', 'scale.data']
            return slots.map((s: string) => <option key={s}>{s}</option>)
          })()}
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

    // Centroid label — one boxed annotation per cluster (a plain text trace reads poorly
    // against similarly-coloured points, so give each label a white pill background instead)
    const clusterAnnotations = groups.map((g: any) => {
      const idx = red.cells.map((_: string, i: number) => i)
        .filter((i: number) => mask[i] && colorVals[i] === g && (!grp || splitMeta[i] === grp))
      if (!idx.length) return null
      return {
        x: idx.reduce((s: number, i: number) => s + red.x[i], 0) / idx.length,
        y: idx.reduce((s: number, i: number) => s + red.y[i], 0) / idx.length,
        text: `<b>${String(g)}</b>`,
        showarrow: false,
        font: { size: 13, color: '#1e293b', family: 'Arial Black, Arial, sans-serif' },
        bgcolor: 'rgba(255,255,255,0.85)',
        bordercolor: '#94a3b8',
        borderwidth: 1,
        borderpad: 3,
      }
    }).filter(Boolean)

    return (
      <div key={grp ?? 'all'} style={{ width: 1120, flexShrink: 0 }}>
        {grp && <div className="text-center text-xs text-slate-500 mb-1">{grp}</div>}
        <Plot key={`${reduction}-${grp ?? 'all'}-${colorBy}`} data={traces} layout={{
          width: 1120, height: 1040,
          title: grp ? undefined : { text: `${reduction} — ${colorBy}`, font: { size: 13 } },
          xaxis: { title: `${reduction}_1`, showgrid: false, zeroline: false, constrain: 'domain' },
          yaxis: { title: `${reduction}_2`, showgrid: false, zeroline: false, scaleanchor: 'x', scaleratio: 1 },
          legend: { itemsizing: 'constant' },
          annotations: clusterAnnotations,
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

// ── Shared vector-PDF export for panel-grid plots (Feature/Violin/Box plots) ────
// Tiles every gene's panel onto a single PDF page at its on-screen grid position,
// embedding the Plotly SVG paths directly (via svg2pdf.js) rather than rasterizing —
// matching what ggsave() would produce for a multi-panel ggplot, so the file opens
// fully editable in Illustrator instead of as a flattened screenshot.
async function downloadPlotGridPdf(
  genes: string[], gridCols: number, panelW: number, panelH: number,
  plotRefs: { current: Record<string, any> }, filenamePrefix: string,
): Promise<void> {
  if (genes.length === 0) return
  const PlotlyLib = (window as any).Plotly
  if (!PlotlyLib) { toast.error('Plotly not ready — try again in a moment'); return }
  const { jsPDF } = await import('jspdf')
  const { svg2pdf } = await import('svg2pdf.js')
  const PX_TO_MM = 0.2646
  const rows  = Math.ceil(genes.length / gridCols)
  const pageW = gridCols * panelW * PX_TO_MM
  const pageH = rows * panelH * PX_TO_MM
  const doc = new jsPDF({ orientation: pageW > pageH ? 'landscape' : 'portrait', unit: 'mm', format: [pageW, pageH] })

  for (let i = 0; i < genes.length; i++) {
    const gd = plotRefs.current[genes[i]]
    if (!gd) continue
    const svgStr: string = await PlotlyLib.toImage(gd, { format: 'svg' })
    // Plotly renders negative tick labels with the Unicode minus sign (U+2212), which
    // jsPDF's built-in fonts (WinAnsi-encoded) can't represent — it falls back to an
    // unrelated glyph (shows up as a stray "). Normalize to a plain ASCII hyphen first.
    const svgText = decodeURIComponent(svgStr.replace(/^data:image\/svg\+xml,/, '')).replace(/−/g, '-')
    const svgEl = new DOMParser().parseFromString(svgText, 'image/svg+xml').querySelector('svg')!
    const col = i % gridCols
    const row = Math.floor(i / gridCols)
    await svg2pdf(svgEl, doc, {
      x: col * panelW * PX_TO_MM, y: row * panelH * PX_TO_MM,
      width: panelW * PX_TO_MM, height: panelH * PX_TO_MM,
    })
  }

  doc.save(`${filenamePrefix}_${genes.join('_').replace(/[^a-zA-Z0-9_-]/g, '_')}.pdf`)
}

// ── Feature plot ───────────────────────────────────────────────────────────────
const MAX_FP_POINTS = 3000

const FP_PANEL_SIZES: Record<number, { w: number; h: number; dot: number; fontSize: number }> = {
  1: { w: 700, h: 660, dot: 6, fontSize: 14 },
  2: { w: 520, h: 490, dot: 5, fontSize: 13 },
  3: { w: 380, h: 360, dot: 4, fontSize: 12 },
  4: { w: 300, h: 280, dot: 3, fontSize: 11 },
}

function FeaturePlotTab({ meta, reduction, assay, slot, selectedClusters, colorBy, sessionId }: any) {
  const [geneInput,      setGeneInput]      = useState('')
  const [exprData,       setExprData]       = useState<Record<string, number[]> | null>(null)
  const [cells,          setCells]          = useState<string[]>([])
  const [loading,        setLoading]        = useState(false)
  const [requestedGenes, setRequestedGenes] = useState<string[]>([])
  const [fetchError,     setFetchError]     = useState<string | null>(null)
  const plotRefs = useRef<Record<string, any>>({})

  const red = meta.reductions[reduction]
  const validGenes = exprData ? Object.keys(exprData) : []
  const gridCols = validGenes.length === 0 ? 1 : validGenes.length === 1 ? 1 : validGenes.length <= 4 ? 2 : validGenes.length <= 9 ? 3 : 4
  const { w: panelW, h: panelH, dot: panelDot, fontSize: panelFontSize } = FP_PANEL_SIZES[gridCols]

  async function fetchExpr() {
    const genes = geneInput.split(',').map((g: string) => g.trim()).filter(Boolean)
    if (!genes.length) { toast.error('Enter at least one gene'); return }
    setLoading(true)
    setFetchError(null)
    setRequestedGenes(genes)
    try {
      const res = await getGeneExpression(sessionId, genes.join(','), assay, slot)
      setExprData(res.expression)
      setCells(res.cells)
      const found = Object.keys(res.expression)
      const missing = genes.filter(g => !found.includes(g))
      if (found.length === 0) toast.error('No genes found — check spelling and case (e.g. Cd3e not cd3e)')
      else if (missing.length) toast(`${missing.join(', ')} not found in dataset`, { icon: '⚠️' })
    } catch (e: any) {
      const msg = e.response?.data?.detail || 'Failed to fetch expression'
      setFetchError(msg)
      setExprData(null)
      toast.error('Expression fetch failed')
    }
    finally { setLoading(false) }
  }

  function clearResults() { setExprData(null); setCells([]); setGeneInput(''); setRequestedGenes([]); setFetchError(null) }

  // Memoize all heavy plot computation — only reruns when data/settings change, not on keystroke
  const plotSection = useMemo(() => {
    if (!exprData || !red) return null
    if (validGenes.length === 0) return null

    const cols = gridCols
    const w = panelW, h = panelH, dot = panelDot, fontSize = panelFontSize

    const idxMap        = Object.fromEntries(cells.map((c: string, i: number) => [c, i]))
    const colorVals     = meta.metadata[colorBy] ?? []
    const metaIndex     = Object.fromEntries(meta.cells.map((c: string, i: number) => [c, i]))
    const clusterGroups = [...new Set(colorVals)] as string[]

    // Subsample indices for rendering — evenly spaced to preserve spatial coverage
    const n_cells  = red.cells.length
    const step     = n_cells > MAX_FP_POINTS ? n_cells / MAX_FP_POINTS : 1
    const subIdx   = Array.from({ length: Math.min(n_cells, MAX_FP_POINTS) }, (_, i) => Math.floor(i * step))
    const subCells = subIdx.map((i: number) => red.cells[i])
    const subX     = subIdx.map((i: number) => red.x[i])
    const subY     = subIdx.map((i: number) => red.y[i])

    // Centroid label — one boxed annotation per cluster (full cell list for accuracy).
    // A plain text trace reads poorly against similarly-coloured points, so give each
    // label a white pill background instead.
    const fullIndices = red.cells.map((_: string, i: number) => i)
    const clusterAnnotations = clusterGroups.map(g => {
      const idx = fullIndices.filter((i: number) => colorVals[metaIndex[red.cells[i]]] === g)
      if (!idx.length) return null
      return {
        x: idx.reduce((s: number, i: number) => s + red.x[i], 0) / idx.length,
        y: idx.reduce((s: number, i: number) => s + red.y[i], 0) / idx.length,
        text: `<b>${String(g)}</b>`,
        showarrow: false,
        font: { size: Math.max(9, fontSize - 2), color: '#1e293b', family: 'Arial Black, Arial, sans-serif' },
        bgcolor: 'rgba(255,255,255,0.85)',
        bordercolor: '#94a3b8',
        borderwidth: 1,
        borderpad: 2,
      }
    }).filter(Boolean)

    return (
      <div style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, ${w}px)`, gap: 12 }}>
        {validGenes.map(gene => {
          const exprVals = exprData[gene]
          const allColor = red.cells.map((c: string) => exprVals[idxMap[c]] ?? 0)
          const subColor = subIdx.map((i: number) => allColor[i])
          const cmin = Math.min(...allColor)
          const cmax = Math.max(...allColor)

          // Sort ascending by expression so high-expression points render on top
          const order = Array.from({ length: subColor.length }, (_, i) => i)
            .sort((a, b) => subColor[a] - subColor[b])
          const sortedX     = order.map(i => subX[i])
          const sortedY     = order.map(i => subY[i])
          const sortedColor = order.map(i => subColor[i])

          const markerTrace = {
            type: 'scatter' as const,
            mode: 'markers' as const,
            x: sortedX, y: sortedY,
            marker: {
              color: sortedColor,
              colorscale: [[0, '#d3d3d3'], [0.05, '#c6dbef'], [0.2, '#6baed6'], [0.5, '#2171b5'], [1, '#08306b']],
              cmin, cmax,
              size: dot, opacity: 0.85,
              showscale: true,
              colorbar: { thickness: 10, len: 0.55, x: 1.02 },
            },
            hoverinfo: 'skip' as const,
            name: gene,
          }

          return (
            <Plot key={`fp-${gene}-${reduction}`} data={[markerTrace]} layout={{
              width: w, height: h,
              title: { text: gene, font: { size: fontSize } },
              xaxis: { title: `${reduction}_1`, showgrid: false, zeroline: false, constrain: 'domain', titlefont: { size: fontSize - 2 } },
              yaxis: { title: `${reduction}_2`, showgrid: false, zeroline: false, scaleanchor: 'x', scaleratio: 1, titlefont: { size: fontSize - 2 } },
              annotations: clusterAnnotations,
              margin: { t: 40, l: 50, r: 55, b: 45 },
              paper_bgcolor: 'transparent', plot_bgcolor: 'transparent',
            }} config={{ responsive: false }}
              onInitialized={(_: any, gd: any) => { plotRefs.current[gene] = gd }}
              onUpdate={(_: any, gd: any) => { plotRefs.current[gene] = gd }} />
          )
        })}
      </div>
    )
  }, [exprData, cells, red, meta, colorBy, reduction, validGenes, gridCols, panelW, panelH, panelDot, panelFontSize])

  const [pdfExporting, setPdfExporting] = useState(false)
  async function handleDownloadPdf() {
    setPdfExporting(true)
    try {
      await downloadPlotGridPdf(validGenes, gridCols, panelW, panelH, plotRefs, 'FeaturePlot')
    } catch (e) {
      toast.error('Download failed: ' + String(e))
    } finally {
      setPdfExporting(false)
    }
  }

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
        {validGenes.length > 0 && (
          <button onClick={handleDownloadPdf} disabled={pdfExporting}
            className="px-3 py-2 text-sm border border-slate-300 rounded-lg hover:bg-slate-50 text-slate-600 disabled:opacity-50">
            {pdfExporting ? 'Exporting…' : '↓ Download PDF (vector)'}
          </button>
        )}
        <CacheBuildButton sessionId={sessionId} assay={assay} slot={slot} />
      </div>

      {exprData && Object.keys(exprData).length === 0 && (
        <p className="text-amber-600 text-sm">No matching genes found for: <strong>{requestedGenes.join(', ')}</strong>. Gene names are case-sensitive.</p>
      )}

      {fetchError && (
        <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700 font-mono whitespace-pre-wrap">
          <span className="font-semibold not-italic">Error: </span>{fetchError}
        </div>
      )}

      {plotSection}
    </div>
  )
}

// ── Violin plot ────────────────────────────────────────────────────────────────
const DIST_PANEL_SIZES: Record<number, { w: number; h: number; fontSize: number }> = {
  1: { w: 900, h: 420, fontSize: 13 },
  2: { w: 540, h: 380, fontSize: 12 },
  3: { w: 370, h: 340, fontSize: 11 },
  4: { w: 280, h: 300, fontSize: 10 },
}

// Shared by the Violin Plot and Box Plot tabs — identical in every way except the
// Plotly trace type and a couple of trace-only options, so both tabs are just this
// component mounted with a different `plotType`.
function DistributionPlotTab({ meta, assay, slot, selectedClusters, colorBy, sessionId, plotType }: any) {
  const [geneInput,      setGeneInput]      = useState('')
  const [exprData,       setExprData]       = useState<Record<string, number[]> | null>(null)
  const [cells,          setCells]          = useState<string[]>([])
  const [loading,        setLoading]        = useState(false)
  const [requestedGenes, setRequestedGenes] = useState<string[]>([])
  const [fetchError,     setFetchError]     = useState<string | null>(null)
  const plotRefs = useRef<Record<string, any>>({})

  const colorVals = meta.metadata[colorBy] ?? []
  const colorMap  = catColorMap(colorVals)
  const groups    = ([...new Set(colorVals)] as string[]).sort()
  const validGenes = exprData ? Object.keys(exprData) : []
  const gridCols   = validGenes.length === 0 ? 1 : validGenes.length === 1 ? 1 : validGenes.length <= 4 ? 2 : validGenes.length <= 9 ? 3 : 4
  const { w: panelW, h: panelH, fontSize: panelFontSize } = DIST_PANEL_SIZES[gridCols]
  const filenamePrefix = plotType === 'box' ? 'BoxPlot' : 'ViolinPlot'

  async function fetchExpr() {
    const genes = geneInput.split(',').map((g: string) => g.trim()).filter(Boolean)
    if (!genes.length) { toast.error('Enter at least one gene'); return }
    setLoading(true)
    setFetchError(null)
    setRequestedGenes(genes)
    try {
      const res = await getGeneExpression(sessionId, genes.join(','), assay, slot)
      setExprData(res.expression)
      setCells(res.cells)
      const found = Object.keys(res.expression)
      const missing = genes.filter(g => !found.includes(g))
      if (found.length === 0) toast.error('No genes found — check spelling and case (e.g. Cd3e not cd3e)')
      else if (missing.length) toast(`${missing.join(', ')} not found in dataset`, { icon: '⚠️' })
    } catch (e: any) {
      const msg = e.response?.data?.detail || 'Failed to fetch expression'
      setFetchError(msg)
      setExprData(null)
      toast.error('Expression fetch failed')
    }
    finally { setLoading(false) }
  }

  function clearResults() { setExprData(null); setCells([]); setGeneInput(''); setRequestedGenes([]); setFetchError(null) }

  const [pdfExporting, setPdfExporting] = useState(false)
  async function handleDownloadPdf() {
    setPdfExporting(true)
    try {
      await downloadPlotGridPdf(validGenes, gridCols, panelW, panelH, plotRefs, filenamePrefix)
    } catch (e) {
      toast.error('Download failed: ' + String(e))
    } finally {
      setPdfExporting(false)
    }
  }

  const plotSection = useMemo(() => {
    if (!exprData) return null
    if (validGenes.length === 0) return null

    const cols = gridCols
    const w = panelW, h = panelH, fontSize = panelFontSize
    const idxMap = Object.fromEntries(cells.map((c, i) => [c, i]))

    return (
      <div style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, ${w}px)`, gap: 12 }}>
        {validGenes.map(gene => {
          const traces = groups.map(grp => {
            const y = meta.cells
              .filter((_: string, i: number) => colorVals[i] === grp)
              .map((c: string) => exprData[gene][idxMap[c]] ?? 0)
            // x0 gives each cluster its own category slot on the x-axis — without it, every
            // trace defaults to the same position (x0 = 0) and all bodies get squeezed into
            // one slot, rendering as near-invisible slivers instead of properly sized shapes.
            return plotType === 'box'
              ? { type: 'box' as const, name: String(grp), x0: String(grp), y, width: 0.7, boxmean: true, boxpoints: 'outliers' as const, marker: { color: colorMap[grp as string] } }
              : { type: 'violin' as const, name: String(grp), x0: String(grp), y, width: 0.85, box: { visible: true }, meanline: { visible: true }, marker: { color: colorMap[grp as string] }, points: false }
          })
          return (
            <Plot key={`dist-${gene}`} data={traces} layout={{
              width: w, height: h,
              title: { text: gene, font: { size: fontSize } },
              xaxis: { title: colorBy, type: 'category', tickangle: -45, tickfont: { size: fontSize - 2 } },
              yaxis: { title: 'Expression', zeroline: false, titlefont: { size: fontSize - 1 } },
              violinmode: 'group',
              violingap: 0.15,
              boxmode: 'group',
              boxgap: 0.15,
              showlegend: false,
              margin: { t: 40, l: 55, r: 15, b: 90 },
              paper_bgcolor: 'transparent', plot_bgcolor: 'transparent',
            }} config={{ responsive: false }}
              onInitialized={(_: any, gd: any) => { plotRefs.current[gene] = gd }}
              onUpdate={(_: any, gd: any) => { plotRefs.current[gene] = gd }} />
          )
        })}
      </div>
    )
  }, [exprData, cells, meta, colorBy, colorVals, groups, colorMap, plotType, validGenes, gridCols, panelW, panelH, panelFontSize])

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
        {validGenes.length > 0 && (
          <button onClick={handleDownloadPdf} disabled={pdfExporting}
            className="px-3 py-2 text-sm border border-slate-300 rounded-lg hover:bg-slate-50 text-slate-600 disabled:opacity-50">
            {pdfExporting ? 'Exporting…' : '↓ Download PDF (vector)'}
          </button>
        )}
        <CacheBuildButton sessionId={sessionId} assay={assay} slot={slot} />
      </div>

      {exprData && Object.keys(exprData).length === 0 && (
        <p className="text-amber-600 text-sm">No matching genes found for: <strong>{requestedGenes.join(', ')}</strong>. Gene names are case-sensitive.</p>
      )}

      {fetchError && (
        <div className="p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700 font-mono whitespace-pre-wrap">
          <span className="font-semibold not-italic">Error: </span>{fetchError}
        </div>
      )}

      {plotSection}
    </div>
  )
}

// ── DGE ───────────────────────────────────────────────────────────────────────
function DGETab({ meta, assay, slot, colorBy, sessionId, mode, onDgeChanged }: any) {
  const [test,    setTest]    = useState('wilcox')
  const [ident1Raw, setIdent1Raw] = useState('')
  const [ident2Raw, setIdent2Raw] = useState('')
  const ident1 = ident1Raw.split(',').map(s => s.trim()).filter(Boolean)
  const ident2 = ident2Raw.split(',').map(s => s.trim()).filter(Boolean)
  const [rmTCR,   setRmTCR]   = useState(true)
  const [rmBCR,   setRmBCR]   = useState(true)
  const [pval,    setPval]    = useState(0.05)
  const [logfc,   setLogfc]   = useState(0.25)
  const [dgeResult, setDgeResult] = useState<DGEResult | null>(null)
  const [loading,   setLoading]   = useState(false)
  const [log,       setLog]       = useState('')
  const [showExcluded, setShowExcluded] = useState(false)
  const [search,    setSearch]    = useState('')
  const [sortCol,   setSortCol]   = useState<string>('avg_log2FC')
  const [sortDir,   setSortDir]   = useState<1 | -1>(-1)
  const [cacheList, setCacheList] = useState<DgeCacheEntry[]>(
    (meta.dge_cache ?? []).filter((e: DgeCacheEntry) => e.mode === mode))
  const [showCache, setShowCache] = useState(true)
  const [loadedCacheKey, setLoadedCacheKey] = useState<string | null>(null)
  const [deletingKey, setDeletingKey] = useState<string | null>(null)

  const results = dgeResult?.markers ?? []

  const groupVals = useMemo(() => [...new Set(meta.metadata[colorBy] ?? [])].sort(), [meta, colorBy])

  async function refreshCacheList() {
    try {
      const list = await listDgeCache(sessionId)
      setCacheList(list.filter(e => e.mode === mode))
    } catch { /* non-fatal — cache panel just stays as-is */ }
  }

  // Cached runs for this Seurat object are available as soon as it's loaded,
  // even before the user presses Run — refetch once the session is known.
  useEffect(() => { refreshCacheList() }, [sessionId, mode])

  async function runAnalysis() {
    setLoading(true); setLog('Running…'); setDgeResult(null); setLoadedCacheKey(null)
    try {
      const res = await runDGE({
        session_id: sessionId, mode, group_by: colorBy,
        assay, slot, test_use: test,
        ident1: ident1.length ? ident1.join(',') : undefined,
        ident2: ident2.length ? ident2.join(',') : undefined,
        rm_tcr: rmTCR, rm_bcr: rmBCR,
        pval_cutoff: pval, logfc_cutoff: logfc,
      })
      const filtered = res.markers.filter((r: any) =>
        r.p_val_adj <= pval && Math.abs(Number(r.avg_log2FC)) >= logfc)
      setDgeResult({ ...res, markers: filtered })
      setLoadedCacheKey(res.cache_key ?? null)
      setLog(`${res.cached ? 'Loaded from cache' : 'Done'} — ${filtered.length} significant DEGs (${res.species} detected). TCR excluded: ${res.excluded_tcr.length}, BCR/Ig excluded: ${res.excluded_bcr.length}.`)
      refreshCacheList()
      onDgeChanged?.()
    } catch (e: any) { setLog('Error: ' + (e.response?.data?.detail || e.message)) }
    finally { setLoading(false) }
  }

  async function loadCachedEntry(entry: DgeCacheEntry) {
    setLoading(true); setLog('Loading cached result…'); setDgeResult(null); setLoadedCacheKey(null)
    try {
      const cached = await loadDgeCacheEntry(sessionId, entry.cache_key)
      setTest(cached.test_use)
      setRmTCR(cached.rm_tcr); setRmBCR(cached.rm_bcr)
      setPval(cached.pval_cutoff); setLogfc(cached.logfc_cutoff)
      if (mode === 'conditions') {
        setIdent1Raw(cached.ident1 ?? ''); setIdent2Raw(cached.ident2 ?? '')
      }
      const filtered = cached.result.markers.filter((r: any) =>
        r.p_val_adj <= cached.pval_cutoff && Math.abs(Number(r.avg_log2FC)) >= cached.logfc_cutoff)
      setDgeResult({ ...cached.result, markers: filtered })
      setLoadedCacheKey(cached.cache_key)
      setLog(`Loaded from cache (run at ${new Date(cached.created_at).toLocaleString()}) — ${filtered.length} significant DEGs (${cached.species} detected).`)
    } catch (e: any) { setLog('Error: ' + (e.response?.data?.detail || e.message)) }
    finally { setLoading(false) }
  }

  async function deleteCachedEntry(entry: DgeCacheEntry) {
    if (!window.confirm(`Delete cached result "${entry.source_label}"? This can't be undone — re-running the same settings will recompute it.`)) return
    setDeletingKey(entry.cache_key)
    try {
      await deleteDgeCacheEntry(sessionId, entry.cache_key)
      setCacheList(prev => prev.filter(e => e.cache_key !== entry.cache_key))
      if (loadedCacheKey === entry.cache_key) setLoadedCacheKey(null)
      onDgeChanged?.()
    } catch (e: any) { toast.error(e.response?.data?.detail || 'Failed to delete cached result') }
    finally { setDeletingKey(null) }
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
    const body   = rows.map(r => DGE_COLS.map(c => JSON.stringify(r[c] ?? '')).join(',')).join('\r\n')
    const blob   = new Blob([`${header}\r\n${body}`], { type: 'text/csv' })
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
                <label className="text-xs text-slate-500 block mb-1">Group 1 <span className="text-slate-400">(comma-separated)</span></label>
                <input value={ident1Raw} onChange={e => setIdent1Raw(e.target.value)}
                  placeholder="e.g. 0,1,3"
                  className="border border-slate-300 rounded px-2 py-1 text-sm w-36 focus:outline-none focus:ring-1 focus:ring-indigo-400" />
              </div>
              <div>
                <label className="text-xs text-slate-500 block mb-1">Group 2 <span className="text-slate-400">(leave blank = all others)</span></label>
                <input value={ident2Raw} onChange={e => setIdent2Raw(e.target.value)}
                  placeholder="e.g. 2,4"
                  className="border border-slate-300 rounded px-2 py-1 text-sm w-36 focus:outline-none focus:ring-1 focus:ring-indigo-400" />
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

      {/* Cached results — lets users load a previous run instead of re-running FindMarkers/FindAllMarkers */}
      <div className="bg-white rounded-lg border border-slate-200 overflow-hidden">
        <button onClick={() => setShowCache(v => !v)}
          className="w-full flex items-center justify-between px-4 py-3 text-sm font-medium text-slate-700 hover:bg-slate-50">
          <span>Cached results{cacheList.length > 0 ? ` (${cacheList.length})` : ''}</span>
          <span className="text-slate-400">{showCache ? '▲' : '▼'}</span>
        </button>
        {showCache && (
          <div className="border-t border-slate-200">
            {cacheList.length === 0 ? (
              <p className="px-4 py-3 text-xs text-slate-400 italic">
                No cached {mode === 'clusters' ? 'FindAllMarkers' : 'FindMarkers'} runs yet for this data — run the analysis above to create one. Once run, it's cached here so it doesn't need to be re-run.
              </p>
            ) : (
              <div className="divide-y divide-slate-100">
                {cacheList.map(entry => (
                  <div key={entry.cache_key}
                    className={`flex flex-wrap items-center gap-x-4 gap-y-1.5 px-4 py-2.5 text-xs ${loadedCacheKey === entry.cache_key ? 'bg-indigo-50' : ''}`}>
                    <span className="font-medium text-slate-700 truncate max-w-[220px]" title={entry.source_label}>
                      {entry.source_label}
                    </span>
                    <span className="text-slate-400">{entry.assay} / {entry.slot}</span>
                    {mode === 'clusters' ? (
                      <span className="text-slate-500">Group by: <b>{entry.group_by}</b></span>
                    ) : (
                      <span className="text-slate-500">
                        <b>{entry.group_by}</b>: {entry.ident1 || '(all)'} <span className="text-slate-400">vs</span> {entry.ident2 || 'others'}
                      </span>
                    )}
                    <span className="text-slate-500">{entry.test_use}</span>
                    {entry.rm_tcr && <span className="px-1.5 py-0.5 bg-purple-100 text-purple-700 rounded-full">TCR removed</span>}
                    {entry.rm_bcr && <span className="px-1.5 py-0.5 bg-blue-100 text-blue-700 rounded-full">BCR removed</span>}
                    <span className="text-slate-500">p ≤ {entry.pval_cutoff}, |log2FC| ≥ {entry.logfc_cutoff}</span>
                    <span className="text-slate-500">{entry.n_significant}/{entry.n_markers} sig.</span>
                    <span className="text-slate-400">({entry.species})</span>
                    <span className="text-slate-400">{new Date(entry.created_at).toLocaleString()}</span>
                    <button onClick={() => loadCachedEntry(entry)} disabled={loading || deletingKey === entry.cache_key}
                      className="ml-auto text-indigo-600 hover:underline font-medium disabled:opacity-50">
                      {loadedCacheKey === entry.cache_key ? 'Loaded' : 'Load'}
                    </button>
                    <button onClick={() => deleteCachedEntry(entry)} disabled={loading || deletingKey === entry.cache_key}
                      className="text-slate-400 hover:text-red-500 font-medium disabled:opacity-50">
                      {deletingKey === entry.cache_key ? 'Deleting…' : 'Delete'}
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
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
        // Restrict to genes actually up/down (not just highest/lowest-ranked) so a gene
        // can never appear in both lists and get double-labeled on the plot.
        const top10up   = sorted.filter((r: any) => Number(r.avg_log2FC) > 0).slice(0, 10)
        const top10down = [...sorted].reverse().filter((r: any) => Number(r.avg_log2FC) < 0).slice(0, 10)

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

        // Symmetric x-range around 0 so log2FC = 0 always sits in the middle of the plot,
        // regardless of whether up- or down-regulated genes have larger fold changes.
        const maxAbsX  = Math.max(...x.map(v => Math.abs(v)), 0.1)
        const xPadding = maxAbsX * 0.15
        const xRange: [number, number] = [-(maxAbsX + xPadding), maxAbsX + xPadding]

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
                width: 950,
                margin: { t: 20, r: 100, b: 50, l: 70 },
                xaxis: { title: { text: 'avg_log2FC' }, range: xRange, zeroline: true, zerolinecolor: '#aaa', zerolinewidth: 1 },
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

          {/* Search + Active cluster table */}
          {clusters.filter(cl => String(cl) === activeTab).map(cl => {
            const COLS = [
              { key: 'gene',        label: 'Gene',       numeric: false },
              { key: 'p_val',       label: 'p_val',      numeric: true  },
              { key: 'p_val_adj',   label: 'p_val_adj',  numeric: true  },
              { key: 'avg_log2FC',     label: 'avg_log2FC',     numeric: true  },
              { key: 'abs_avg_log2FC', label: '|avg_log2FC|',   numeric: true  },
              { key: 'pct.1',          label: 'pct.1',          numeric: true  },
              { key: 'pct.2',          label: 'pct.2',          numeric: true  },
            ]

            function toggleSort(col: string) {
              if (sortCol === col) setSortDir(d => (d === 1 ? -1 : 1) as 1 | -1)
              else { setSortCol(col); setSortDir(-1) }
            }

            const clRows = results
              .filter((r: any) => r.cluster === cl)
              .filter((r: any) => !search || String(r.gene).toLowerCase().includes(search.toLowerCase()))
              .sort((a: any, b: any) => {
                const av = COLS.find(c => c.key === sortCol)?.numeric ? Number(a[sortCol]) : String(a[sortCol])
                const bv = COLS.find(c => c.key === sortCol)?.numeric ? Number(b[sortCol]) : String(b[sortCol])
                return av < bv ? sortDir : av > bv ? -sortDir : 0
              })

            const SortIcon = ({ col }: { col: string }) => (
              <span className="ml-1 text-slate-400">
                {sortCol === col ? (sortDir === -1 ? '▼' : '▲') : '⇅'}
              </span>
            )

            return (
              <div key={String(cl)}>
                <div className="flex items-center justify-between px-4 py-2 border-b bg-slate-50 gap-3">
                  <input
                    value={search}
                    onChange={e => setSearch(e.target.value)}
                    placeholder="Search gene…"
                    className="border border-slate-300 rounded px-2 py-1 text-xs w-40 focus:outline-none focus:ring-1 focus:ring-indigo-400"
                  />
                  <span className="text-xs text-slate-500">{clRows.length} DEGs</span>
                  <button onClick={() => downloadCSV(clRows, `dge_cluster_${cl}.csv`)}
                    className="text-xs text-indigo-500 hover:underline ml-auto">⬇ CSV</button>
                </div>
                <div className="overflow-auto max-h-[55vh]">
                  <table className="w-full text-xs">
                    <thead className="bg-slate-50 border-b sticky top-0">
                      <tr>
                        {COLS.map(c => (
                          <th key={c.key}
                            onClick={() => toggleSort(c.key)}
                            className="text-left px-3 py-2 font-medium cursor-pointer hover:bg-slate-100 select-none whitespace-nowrap">
                            {c.label}<SortIcon col={c.key} />
                          </th>
                        ))}
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
                          <td className="px-3 py-1.5 font-mono text-slate-600">{Math.abs(Number(r.avg_log2FC)).toFixed(3)}</td>
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
  const allCols = ['cell', ...cols]
  const [filter,  setFilter]  = useState('')
  const [sortCol, setSortCol] = useState('cell')
  const [sortDir, setSortDir] = useState<1 | -1>(1)

  function toggleSort(col: string) {
    if (sortCol === col) setSortDir(d => (d === 1 ? -1 : 1) as 1 | -1)
    else { setSortCol(col); setSortDir(1) }
  }

  const visible = rows
    .filter(r => !filter || Object.values(r).some(v => String(v).toLowerCase().includes(filter.toLowerCase())))
    .sort((a, b) => {
      const av = a[sortCol]; const bv = b[sortCol]
      const an = Number(av); const bn = Number(bv)
      if (!isNaN(an) && !isNaN(bn)) return (an - bn) * sortDir
      return String(av).localeCompare(String(bv)) * sortDir
    })

  return (
    <div className="p-4 space-y-3">
      <div className="flex items-center gap-3">
        <input value={filter} onChange={e => setFilter(e.target.value)}
          placeholder="Search across all columns…"
          className="border border-slate-300 rounded px-3 py-1.5 text-sm w-72 focus:outline-none focus:ring-1 focus:ring-indigo-400" />
        {filter && (
          <button onClick={() => setFilter('')}
            className="text-xs text-slate-400 hover:text-red-500">✕ Clear</button>
        )}
        <span className="text-xs text-slate-400 ml-auto">
          Showing {Math.min(visible.length, 500)} of {visible.length} cells
        </span>
      </div>
      <div className="overflow-auto rounded-lg border border-slate-200 max-h-[60vh]">
        <table className="text-xs w-full">
          <thead className="bg-slate-50 border-b sticky top-0">
            <tr>
              {allCols.map(c => (
                <th key={c} onClick={() => toggleSort(c)}
                  className="text-left px-3 py-2 font-medium whitespace-nowrap cursor-pointer hover:bg-slate-100 select-none">
                  {c}
                  <span className="ml-1 text-slate-400">
                    {sortCol === c ? (sortDir === 1 ? '▲' : '▼') : '⇅'}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y">
            {visible.slice(0, 500).map((row, i) => (
              <tr key={i} className="hover:bg-slate-50">
                {allCols.map(c => (
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

// ── Pathway Analysis tab ───────────────────────────────────────────────────────
const MSIGDB_CAT_LABEL: Record<string, string> = {
  H:  'Hallmark',
  C1: 'C1 — Positional',
  C2: 'C2 — Curated',
  C3: 'C3 — Regulatory',
  C4: 'C4 — Computational',
  C5: 'C5 — Ontology',
  C6: 'C6 — Oncogenic',
  C7: 'C7 — Immunologic',
  C8: 'C8 — Cell type',
  M1: 'M1 — Positional (mouse)',
  M2: 'M2 — Curated (mouse)',
  M3: 'M3 — Regulatory (mouse)',
  M4: 'M4 — Computational (mouse)',
  M5: 'M5 — Ontology (mouse)',
  M6: 'M6 — Oncogenic (mouse)',
  M7: 'M7 — Immunologic (mouse)',
  M8: 'M8 — Cell type (mouse)',
}

function pathwayLabel(key: string): string {
  const fixed: Record<string, string> = {
    'ORA.FULL.GO':   'ORA — GO (all sig.)',
    'ORA.UP.GO':     'ORA — GO (up)',
    'ORA.DOWN.GO':   'ORA — GO (down)',
    'ORA.FULL.KEGG': 'ORA — KEGG (all)',
    'ORA.UP.KEGG':   'ORA — KEGG (up)',
    'ORA.DOWN.KEGG': 'ORA — KEGG (down)',
    'ORA.FULL.WP':   'ORA — WikiPathways (all)',
    'ORA.UP.WP':     'ORA — WikiPathways (up)',
    'ORA.DOWN.WP':   'ORA — WikiPathways (down)',
    'GSEA.GO':       'GSEA — GO',
    'GSEA.KEGG':     'GSEA — KEGG',
    'GSEA.WP':       'GSEA — WikiPathways',
  }
  if (fixed[key]) return fixed[key]
  // ORA.FULL.MSigDB.C2 → ORA — MSigDB C2 — Curated
  // GSEA.MSigDB.H      → GSEA — MSigDB Hallmark
  const oraMatch  = key.match(/^ORA\.FULL\.MSigDB\.(.+)$/)
  const gseaMatch = key.match(/^GSEA\.MSigDB\.(.+)$/)
  const cat = (oraMatch ?? gseaMatch)?.[1]
  if (cat) {
    const catLabel = MSIGDB_CAT_LABEL[cat] ?? cat
    return oraMatch ? `ORA — MSigDB ${catLabel}` : `GSEA — MSigDB ${catLabel}`
  }
  return key
}

function downloadCSVData(rows: Record<string, unknown>[], filename: string) {
  if (!rows.length) return
  const cols = Object.keys(rows[0])
  const escape = (v: unknown) => {
    const s = String(v ?? '')
    return /[,"\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
  }
  const csv = [cols.join(','), ...rows.map(r => cols.map(c => escape(r[c])).join(','))].join('\r\n')
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv' }))
  const a = document.createElement('a'); a.href = url; a.download = filename; a.click()
  URL.revokeObjectURL(url)
}

function PathwayResultTable({ rows, label }: { rows: Record<string, unknown>[]; label: string }) {
  const [search, setSearch] = useState('')
  const [sortCol, setSortCol] = useState('')
  const [sortDir, setSortDir] = useState<1 | -1>(-1)

  if (!rows || rows.length === 0) return <p className="text-xs text-slate-400 p-4">No results.</p>
  if ('status' in rows[0]) return <p className="text-xs text-slate-400 p-4">{String(rows[0].status)}</p>

  const cols = Object.keys(rows[0]).filter(c => c !== 'geneID' && c !== 'idx')
  const allCols = [...cols, 'geneID']

  function toggleSort(col: string) {
    if (sortCol === col) setSortDir(d => (d === 1 ? -1 : 1) as 1 | -1)
    else { setSortCol(col); setSortDir(-1) }
  }

  const visible = rows
    .filter(r => !search || Object.values(r).some(v => String(v ?? '').toLowerCase().includes(search.toLowerCase())))
    .sort((a, b) => {
      if (!sortCol) return 0
      const av = a[sortCol]; const bv = b[sortCol]
      const an = Number(av); const bn = Number(bv)
      if (!isNaN(an) && !isNaN(bn)) return (an - bn) * sortDir
      return String(av ?? '').localeCompare(String(bv ?? '')) * sortDir
    })

  const safeFilename = label.replace(/[^a-zA-Z0-9_-]/g, '_') + '.csv'

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-3">
        <input value={search} onChange={e => setSearch(e.target.value)}
          placeholder="Search…"
          className="border border-slate-300 rounded px-3 py-1.5 text-sm w-64 focus:outline-none focus:ring-1 focus:ring-indigo-400" />
        {search && <button onClick={() => setSearch('')} className="text-xs text-slate-400 hover:text-red-500">✕ Clear</button>}
        <span className="text-xs text-slate-400">
          Showing {Math.min(visible.length, 200)} of {visible.length} pathways
        </span>
        <button onClick={() => downloadCSVData(rows, safeFilename)}
          className="ml-auto px-3 py-1.5 text-xs border border-slate-300 rounded hover:bg-slate-50 text-slate-600 flex items-center gap-1">
          ↓ Download CSV
        </button>
      </div>
      <div className="overflow-auto rounded-lg border border-slate-200 max-h-[55vh]">
        <table className="text-xs w-full">
          <thead className="bg-slate-50 border-b sticky top-0">
            <tr>
              {allCols.map(c => (
                <th key={c} onClick={() => c !== 'geneID' && toggleSort(c)}
                  className={`text-left px-3 py-2 font-medium whitespace-nowrap select-none ${c !== 'geneID' ? 'cursor-pointer hover:bg-slate-100' : ''}`}>
                  {c === '_row' ? 'ID' : c}
                  {c !== 'geneID' && (
                    <span className="ml-1 text-slate-400">
                      {sortCol === c ? (sortDir === 1 ? '▲' : '▼') : '⇅'}
                    </span>
                  )}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y">
            {visible.slice(0, 200).map((row, i) => (
              <tr key={i} className="hover:bg-slate-50">
                {allCols.map(c => (
                  <td key={c} className="px-3 py-1.5 text-slate-600 max-w-xs truncate whitespace-nowrap"
                    title={String(row[c] ?? '')}>
                    {String(row[c] ?? '')}
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

function parseGeneRatio(val: unknown): number {
  if (typeof val === 'number') return val
  const s = String(val ?? '')
  const [a, b] = s.split('/').map(Number)
  return (b > 0) ? a / b : 0
}

function PathwayDotplot({ rows, label }: { rows: Record<string, unknown>[]; label: string }) {
  const graphDivRef = useRef<any>(null)

  async function handleDownloadPdf() {
    if (!graphDivRef.current) return
    try {
      const PlotlyLib = (window as any).Plotly
      if (!PlotlyLib) { toast.error('Plotly not ready — try again in a moment'); return }

      // Get SVG string from Plotly (vector, Illustrator-compatible)
      const svgStr: string = await PlotlyLib.toImage(graphDivRef.current, { format: 'svg' })
      // Plotly renders negative tick labels with the Unicode minus sign (U+2212), which
      // jsPDF's built-in fonts (WinAnsi-encoded) can't represent — it falls back to an
      // unrelated glyph (shows up as a stray "). Normalize to a plain ASCII hyphen first.
      const svgText = decodeURIComponent(svgStr.replace(/^data:image\/svg\+xml,/, '')).replace(/−/g, '-')

      // Parse dimensions from SVG viewBox / width / height
      const parser = new DOMParser()
      const svgDoc = parser.parseFromString(svgText, 'image/svg+xml')
      const svgEl  = svgDoc.querySelector('svg')!
      const svgW   = parseFloat(svgEl.getAttribute('width')  ?? '800')
      const svgH   = parseFloat(svgEl.getAttribute('height') ?? '600')

      // jsPDF uses mm; 1px = 0.2646 mm at 96 dpi
      const mmW = svgW * 0.2646
      const mmH = svgH * 0.2646

      const { jsPDF } = await import('jspdf')
      const { svg2pdf } = await import('svg2pdf.js')

      const doc = new jsPDF({
        orientation: mmW > mmH ? 'landscape' : 'portrait',
        unit: 'mm',
        format: [mmW, mmH],
      })

      await svg2pdf(svgEl, doc, { x: 0, y: 0, width: mmW, height: mmH })

      doc.save(`${label.replace(/[^a-zA-Z0-9_-]/g, '_')}.pdf`)
    } catch (e) {
      toast.error('Download failed: ' + String(e))
    }
  }

  if (!rows || rows.length === 0 || 'status' in rows[0]) return null
  const adjCol = 'p.adjust' in rows[0] ? 'p.adjust' : 'pvalue'
  const isGSEA = 'NES' in rows[0]

  // Sort by GeneRatio (ORA) or |NES| (GSEA) descending; take top 20
  // Reverse at the end so the highest ratio appears at the top of the y-axis
  const sortKey = isGSEA
    ? (r: Record<string, unknown>) => Math.abs(Number(r.NES ?? 0))
    : (r: Record<string, unknown>) => parseGeneRatio(r.GeneRatio ?? r.generatio ?? 0)
  const top = [...rows]
    .sort((a, b) => sortKey(b) - sortKey(a))
    .slice(0, 20)
    .reverse()

  const labels = top.map(r => String(r.Description ?? r.ID ?? ''))
  const padj   = top.map(r => Number(r[adjCol] ?? 1))
  const pMin   = Math.min(...padj)
  const pMax   = Math.max(...padj)

  // x: GeneRatio (ORA) or NES (GSEA, can be negative = down-regulated)
  const x      = isGSEA
    ? top.map(r => Number(r.NES ?? 0))
    : top.map(r => parseGeneRatio(r.GeneRatio ?? r.generatio ?? 0))
  const xLabel = isGSEA ? 'NES' : 'GeneRatio'

  // Dot size proportional to Count (ORA) or setSize (GSEA)
  const counts    = top.map(r => Number(r.Count ?? r.setSize ?? 10))
  const countMax  = Math.max(...counts, 1)
  const dotSizes  = counts.map(c => 8 + (c / countMax) * 22)
  const sizeLabel = isGSEA ? 'setSize' : 'Count'

  const hoverText = top.map((r, i) => [
    `<b>${labels[i]}</b>`,
    isGSEA
      ? `NES: ${Number(r.NES ?? 0).toFixed(3)}`
      : `GeneRatio: ${x[i].toFixed(4)} (${r.GeneRatio ?? ''})`,
    `${sizeLabel}: ${counts[i]}`,
    `p.adjust: ${padj[i].toExponential(2)}`,
  ].join('<br>'))

  const safeLabel = label.replace(/[^a-zA-Z0-9_-]/g, '_')

  return (
    <div>
      <div className="flex justify-end mb-1">
        <button onClick={handleDownloadPdf}
          className="px-3 py-1.5 text-xs border border-slate-300 rounded hover:bg-slate-50 text-slate-600 flex items-center gap-1">
          ↓ Download PDF (300 dpi)
        </button>
      </div>
    <Plot
      onInitialized={(_, gd) => { graphDivRef.current = gd }}
      onUpdate={(_, gd)      => { graphDivRef.current = gd }}
      data={[{
        type: 'scatter',
        mode: 'markers',
        x,
        y: labels,
        marker: {
          size: dotSizes,
          color: padj,
          colorscale: [['0', '#dc2626'], ['0.5', '#f97316'], ['1', '#3b82f6']],
          cmin: 0,
          cmax: 1,
          reversescale: false,
          colorbar: {
            title: { text: 'p.adjust', side: 'right' },
            thickness: 14,
            len: 0.6,
          },
          line: { color: '#94a3b8', width: 0.5 },
        },
        text: hoverText,
        hoverinfo: 'text',
      }]}
      layout={{
        margin: { l: 320, r: 160, t: 30, b: 70 },
        height: Math.max(400, top.length * 48 + 100),
        width: Math.max(960, top.length * 24 + 560),
        xaxis: {
          title: xLabel,
          zeroline: isGSEA,
          zerolinecolor: '#94a3b8',
        },
        yaxis: { automargin: true, tickfont: { size: 11 } },
        paper_bgcolor: 'transparent',
        plot_bgcolor: 'transparent',
        // Invisible legend-like annotation for dot size
        annotations: [
          { x: 1.18, y: 1.05, xref: 'paper', yref: 'paper',
            text: `<b>${sizeLabel}</b>`, showarrow: false,
            font: { size: 11, color: '#64748b' }, xanchor: 'center' },
          ...[0.25, 0.5, 1.0].map((frac, i) => ({
            x: 1.18, y: 0.85 - i * 0.15, xref: 'paper' as const, yref: 'paper' as const,
            text: `${Math.round(frac * countMax)}`,
            showarrow: false, font: { size: 10, color: '#64748b' }, xanchor: 'center' as const,
          })),
        ],
      }}
      config={{ displayModeBar: false, responsive: false }}
    />
    </div>
  )
}

// ── Per-method explanation ─────────────────────────────────────────────────────
const METHOD_INFO: Record<string, { what: string; columns: { col: string; meaning: string }[] }> = {
  ORA: {
    what: 'Over-Representation Analysis (ORA) tests whether your significant gene list contains more members of a gene set than expected by chance (Fisher\'s exact test / hypergeometric test). Only genes passing the p-value cutoff are used.',
    columns: [
      { col: 'GeneRatio', meaning: 'k/n — fraction of your significant genes that belong to this term.' },
      { col: 'BgRatio',   meaning: 'K/N — fraction of all background genes that belong to this term.' },
      { col: 'pvalue',    meaning: 'Raw hypergeometric p-value.' },
      { col: 'p.adjust',  meaning: 'BH-adjusted p-value. Use this as the primary significance filter.' },
      { col: 'qvalue',    meaning: 'FDR q-value (Storey method). An alternative to p.adjust.' },
      { col: 'Count',     meaning: 'Number of your significant genes in this term — the bar length in the chart.' },
      { col: 'geneID',    meaning: 'Gene symbols that overlap between your list and this term.' },
    ],
  },
  GSEA: {
    what: 'Gene Set Enrichment Analysis (GSEA) uses the full ranked gene list (sorted by log₂FC) and asks whether the members of a gene set are concentrated at the top or bottom of the ranking — without a significance cutoff. It is more sensitive than ORA for detecting pathway shifts.',
    columns: [
      { col: 'NES',       meaning: 'Normalized Enrichment Score. Positive = gene set enriched in up-regulated genes; negative = enriched in down-regulated genes.' },
      { col: 'pvalue',    meaning: 'Raw GSEA p-value (permutation-based).' },
      { col: 'p.adjust',  meaning: 'BH-adjusted p-value across all tested gene sets.' },
      { col: 'setSize',   meaning: 'Number of genes in this gene set that were present in your ranked list — the bar length in the chart.' },
      { col: 'geneID',    meaning: 'Leading-edge genes: the subset that drives the enrichment score.' },
    ],
  },
}

const DATABASE_INFO: Record<string, string> = {
  GO:    'Gene Ontology (GO) — three independent sub-ontologies: Biological Process (BP), Molecular Function (MF), and Cellular Component (CC). Covers most annotated gene functions.',
  KEGG:  'KEGG Pathway database — curated metabolic and signalling pathways. Gene IDs are ENTREZ-based; geneID column has been converted back to gene symbols.',
  WP:    'WikiPathways — community-curated, freely editable pathways. Broader coverage of emerging biology than KEGG.',
  MSigDB_H:  'MSigDB Hallmark — 50 well-defined biological states representing coherent and specific biological processes. Good starting point for high-level interpretation.',
  MSigDB_C1: 'MSigDB C1 — Positional gene sets: one set per cytogenetic band. Useful for detecting chromosomal amplifications or deletions.',
  MSigDB_C2: 'MSigDB C2 — Curated gene sets from pathway databases (KEGG, Reactome, BioCarta) and published literature. Very large collection.',
  MSigDB_C3: 'MSigDB C3 — Regulatory targets: genes sharing a transcription factor binding site (TFT) or miRNA seed sequence (MIR). Useful for upstream regulator analysis.',
  MSigDB_C4: 'MSigDB C4 — Computational gene sets defined by mining cancer microarray data. Cancer-focused.',
  MSigDB_C5: 'MSigDB C5 — Gene Ontology gene sets (BP, MF, CC). Overlaps with direct GO analysis but uses MSigDB curation.',
  MSigDB_C6: 'MSigDB C6 — Oncogenic signatures: gene sets up- or down-regulated by known oncogenes and tumour suppressors.',
  MSigDB_C7: 'MSigDB C7 — Immunologic signatures: gene sets representing cell states and perturbations in the immune system (ImmuneSigDB).',
  MSigDB_C8: 'MSigDB C8 — Cell type signature gene sets from single-cell studies. Useful for cell type deconvolution.',
  MSigDB_M1: 'MSigDB M1 — Mouse positional gene sets (one per cytogenetic band).',
  MSigDB_M2: 'MSigDB M2 — Mouse curated gene sets (Reactome, WikiPathways, literature).',
  MSigDB_M3: 'MSigDB M3 — Mouse regulatory target gene sets (TFT, MIR).',
  MSigDB_M5: 'MSigDB M5 — Mouse Gene Ontology gene sets (BP, MF, CC).',
  MSigDB_M8: 'MSigDB M8 — Mouse cell type signature gene sets from single-cell studies.',
}

function PathwayMethodExplanation({ methodKey, rows }: {
  methodKey: string
  rows: Record<string, unknown>[]
}) {
  const [open, setOpen] = useState(false)

  const isGSEA = methodKey.startsWith('GSEA')
  const methodType = isGSEA ? 'GSEA' : 'ORA'
  const info = METHOD_INFO[methodType]

  // Derive database label from key, e.g. ORA.FULL.MSigDB.C2 → MSigDB_C2
  let dbKey = ''
  if (methodKey.includes('GO'))     dbKey = 'GO'
  else if (methodKey.includes('KEGG')) dbKey = 'KEGG'
  else if (methodKey.includes('.WP'))  dbKey = 'WP'
  else {
    const m = methodKey.match(/MSigDB\.(.+)$/)
    if (m) dbKey = `MSigDB_${m[1]}`
  }
  const dbInfo = DATABASE_INFO[dbKey]

  const hasNoResults = rows.length === 0 || ('status' in rows[0])
  const resultCount  = hasNoResults ? 0 : rows.length

  // Which columns from the explanation actually appear in the data
  const dataCols = rows.length > 0 && !('status' in rows[0]) ? Object.keys(rows[0]) : []
  const relevantCols = info.columns.filter(c => dataCols.includes(c.col))

  return (
    <div className="rounded-lg border border-slate-200 bg-slate-50 text-xs text-slate-600 overflow-hidden">
      <button
        onClick={() => setOpen(o => !o)}
        className="w-full flex items-center justify-between px-4 py-2.5 hover:bg-slate-100 transition-colors text-left">
        <div className="flex items-center gap-3">
          <span className="font-medium text-slate-700">{pathwayLabel(methodKey)}</span>
          {hasNoResults
            ? <span className="text-slate-400">no significant results</span>
            : <span className="text-indigo-600 font-medium">{resultCount} enriched terms</span>}
          {!hasNoResults && isGSEA && (() => {
            const pos = rows.filter(r => Number(r.NES ?? 0) > 0).length
            const neg = rows.filter(r => Number(r.NES ?? 0) < 0).length
            return <span className="text-slate-400">{pos} up · {neg} down</span>
          })()}
        </div>
        <span className="text-slate-400 ml-2">{open ? '▲ hide explanation' : '▼ show explanation'}</span>
      </button>

      {open && (
        <div className="px-4 pb-4 pt-1 space-y-3 border-t border-slate-200 bg-white">
          {/* Method */}
          <div>
            <p className="font-medium text-slate-700 mb-0.5">{methodType} method</p>
            <p className="text-slate-500 leading-relaxed">{info.what}</p>
          </div>

          {/* Database */}
          {dbInfo && (
            <div>
              <p className="font-medium text-slate-700 mb-0.5">Gene set database</p>
              <p className="text-slate-500 leading-relaxed">{dbInfo}</p>
            </div>
          )}

          {/* Chart legend */}
          {!hasNoResults && (
            <div>
              <p className="font-medium text-slate-700 mb-0.5">Bar chart</p>
              <p className="text-slate-500 leading-relaxed">
                Top 20 terms by adjusted p-value.
                {isGSEA
                  ? ' X = NES (positive = up-regulated pathway, negative = down-regulated). Dot size = setSize (genes in your ranked list matching the set). Dot colour = p.adjust (red = most significant, blue = least significant).'
                  : ' X = GeneRatio (k/n, fraction of your significant genes in the term). Dot size = Count (number of overlapping genes). Dot colour = p.adjust (red = most significant, blue = least significant).'}
              </p>
            </div>
          )}

          {/* Column guide */}
          {relevantCols.length > 0 && (
            <div>
              <p className="font-medium text-slate-700 mb-1">Table columns</p>
              <dl className="space-y-1">
                {relevantCols.map(({ col, meaning }) => (
                  <div key={col} className="flex gap-2">
                    <dt className="font-mono text-indigo-700 shrink-0 w-28">{col}</dt>
                    <dd className="text-slate-500">{meaning}</dd>
                  </div>
                ))}
              </dl>
            </div>
          )}

          {/* GSEA NES hint */}
          {!hasNoResults && isGSEA && (
            <div className="bg-amber-50 border border-amber-100 rounded px-3 py-2 text-amber-700">
              NES &gt; 0 → gene set enriched among <strong>up-regulated</strong> genes.
              NES &lt; 0 → enriched among <strong>down-regulated</strong> genes.
              Sort the table by NES to separate activated from repressed pathways.
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function PathwayTab({ meta, sessionId, dgeVersion = 0 }: {
  meta: SeuratMeta; sessionId: string
  dgeVersion?: number  // bumped whenever a DGE run/load/delete happens elsewhere, to trigger a refetch
}) {
  // Pathway analysis compares two groups, which only maps cleanly to DGE — Conditions
  // results (DGE — Clusters is one-vs-rest per cluster) — so only offer those here.
  // Sourced directly from the backend's persisted DGE cache (not from in-session component
  // state) so results already cached from a previous session — e.g. a preset that already
  // has DGE runs — show up immediately, without needing to re-run or "Load" them first.
  const [conditionsDgeResults, setConditionsDgeResults] = useState<DgeCacheEntry[]>([])

  useEffect(() => {
    let cancelled = false
    listDgeCache(sessionId).then(list => {
      if (!cancelled) setConditionsDgeResults(list.filter(e => e.mode === 'conditions'))
    }).catch(() => {})
    return () => { cancelled = true }
  }, [sessionId, dgeVersion])

  const [species,     setSpecies]     = useState<'auto' | 'hsa' | 'mmu'>('auto')
  const [pvalCutoff,  setPvalCutoff]  = useState(0.05)
  const [csvInput,    setCsvInput]    = useState<'session' | 'paste' | 'upload'>('session')
  const [selectedSaved, setSelectedSaved] = useState(0)
  const [pastedGenes, setPastedGenes] = useState('')
  const [uploadedFile, setUploadedFile] = useState<File | null>(null)
  const [taskId,      setTaskId]      = useState<string | null>(null)
  const [status,      setStatus]      = useState<'idle' | 'running' | 'done' | 'error'>('idle')
  const [results,     setResults]     = useState<Record<string, Record<string, unknown>[]> | null>(null)
  const [error,       setError]       = useState<string | null>(null)
  const [log,         setLog]         = useState<string>('')
  const [activeMethod, setActiveMethod] = useState<string>('')
  const logRef = useRef<HTMLPreElement>(null)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  // Auto-switch to session tab and select newest result when DGE — Conditions results arrive
  const prevSavedLen = useRef(0)
  useEffect(() => {
    if (conditionsDgeResults.length > prevSavedLen.current) {
      setCsvInput('session')
      setSelectedSaved(0)
    }
    prevSavedLen.current = conditionsDgeResults.length
  }, [conditionsDgeResults.length])

  useEffect(() => {
    if (!taskId || status !== 'running') return
    pollRef.current = setInterval(async () => {
      try {
        const res = await getPathwayResult(taskId)
        if (res.log) {
          setLog(res.log)
          setTimeout(() => { if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight }, 50)
        }
        if (res.status === 'done') {
          clearInterval(pollRef.current!)
          setStatus('done')
          const r = res.results ?? {}
          setResults(r)
          setActiveMethod(Object.keys(r)[0] ?? '')
        } else if (res.status === 'error') {
          clearInterval(pollRef.current!)
          setStatus('error')
          setError(res.error ?? 'Unknown error')
        } else if ((res.status as string) === 'cancelled') {
          clearInterval(pollRef.current!)
          setStatus('idle')
        }
      } catch {}
    }, 5000)
    return () => { if (pollRef.current) clearInterval(pollRef.current) }
  }, [taskId, status])

  async function handleRun() {
    let csvData = ''

    if (csvInput === 'session') {
      const entry = conditionsDgeResults[selectedSaved]
      if (!entry) { toast.error('No DGE result selected'); return }
      let markers: Record<string, unknown>[]
      try {
        const cached = await loadDgeCacheEntry(sessionId, entry.cache_key)
        markers = cached.result.markers
      } catch (e: any) {
        toast.error(e.response?.data?.detail || 'Failed to load cached DGE result')
        return
      }
      if (markers.length === 0) { toast.error('Selected DGE result has no markers'); return }
      // Normalize column names: rename to standard format expected by the R script
      const rows = markers.map((r: any) => ({
        gene:    r.gene,
        pval:    r.p_val    ?? r.pval    ?? 1,
        logFC:   r.avg_log2FC ?? r.logFC  ?? 0,
        padj:    r.p_val_adj ?? r.padj   ?? 1,
        absLogFC: Math.abs(Number(r.avg_log2FC ?? r.logFC ?? 0)),
      }))
      csvData = JSON.stringify(rows)

    } else if (csvInput === 'paste') {
      if (!pastedGenes.trim()) { toast.error('Paste a gene list first'); return }
      const lines = pastedGenes.trim().split('\n')
      const hasHeader = isNaN(Number(lines[0].split(',')[1]))
      const header = hasHeader ? lines[0].split(',') : ['gene', 'pval', 'logFC', 'padj', 'absLogFC']
      const rows = (hasHeader ? lines.slice(1) : lines).map(l => {
        const parts = l.split(',')
        return Object.fromEntries(header.map((h, i) => [h.trim(), parts[i]?.trim() ?? '']))
      })
      csvData = JSON.stringify(rows)

    } else {
      if (!uploadedFile) { toast.error('Upload a CSV file first'); return }
      const text = await uploadedFile.text()
      const lines = text.trim().split('\n')
      const header = lines[0].split(',').map(s => s.trim().replace(/^"|"$/g, ''))
      const rows = lines.slice(1).map(l => {
        const parts = l.split(',')
        return Object.fromEntries(header.map((h, i) => [h, parts[i]?.trim().replace(/^"|"$/g, '') ?? '']))
      })
      csvData = JSON.stringify(rows)
    }

    setStatus('running')
    setResults(null)
    setError(null)
    setLog('')
    try {
      const { task_id } = await startPathwayAnalysis({ session_id: sessionId, csv_data: csvData, species, pval_cutoff: pvalCutoff })
      setTaskId(task_id)
      toast.success('Pathway analysis started — this may take 5–15 minutes')
    } catch (e: any) {
      setStatus('error')
      setError(e.response?.data?.detail ?? String(e))
    }
  }

  const methods = results ? Object.keys(results) : []

  return (
    <div className="p-4 space-y-4">
      {/* Controls */}
      <div className="bg-white rounded-xl border border-slate-200 p-4 space-y-4">
        <h3 className="font-semibold text-slate-700">Pathway Analysis</h3>
        <p className="text-xs text-slate-400">
          Runs ORA and GSEA against GO, KEGG, WikiPathways, and MSigDB (H + C1–C9 for human, H + M1–M8 for mouse) using clusterProfiler.
          Provide a ranked gene list from a DGE result (columns: gene, pval / p_val, logFC / avg_log2FC, padj / p_val_adj).
        </p>

        <div className="flex flex-wrap gap-4 items-end">
          <div>
            <label className="text-xs text-slate-500 block mb-1">Species</label>
            <select value={species} onChange={e => setSpecies(e.target.value as 'auto' | 'hsa' | 'mmu')}
              className="border border-slate-300 rounded px-3 py-1.5 text-sm">
              <option value="auto">Auto-detect</option>
              <option value="hsa">Human (hsa)</option>
              <option value="mmu">Mouse (mmu)</option>
            </select>
          </div>
          <div>
            <label className="text-xs text-slate-500 block mb-1">p-value cutoff</label>
            <input type="number" step="0.01" min="0.001" max="0.2"
              value={pvalCutoff} onChange={e => setPvalCutoff(Number(e.target.value))}
              className="border border-slate-300 rounded px-3 py-1.5 text-sm w-24" />
          </div>
          <div>
            <label className="text-xs text-slate-500 block mb-1">Gene list source</label>
            <div className="flex rounded overflow-hidden border border-slate-300 text-sm">
              {(['session', 'paste', 'upload'] as const).map(m => (
                <button key={m} onClick={() => setCsvInput(m)}
                  className={`px-3 py-1.5 ${csvInput === m ? 'bg-indigo-600 text-white' : 'bg-white text-slate-600 hover:bg-slate-50'}`}>
                  {m === 'session' ? 'From DGE' : m === 'paste' ? 'Paste CSV' : 'Upload CSV'}
                </button>
              ))}
            </div>
          </div>
        </div>

        {csvInput === 'session' ? (
          <div className="space-y-2">
            {conditionsDgeResults.length === 0 ? (
              <p className="text-xs text-slate-400 bg-slate-50 rounded p-3 border border-slate-200">
                No DGE — Conditions results yet. Run a DGE analysis in the <strong>DGE — Conditions</strong> tab first — results will appear here automatically.
              </p>
            ) : (
              <div className="space-y-2">
                {conditionsDgeResults.map((r, i) => (
                  <label key={r.cache_key} className={`flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-colors
                    ${selectedSaved === i ? 'border-indigo-400 bg-indigo-50' : 'border-slate-200 hover:border-slate-300 bg-white'}`}>
                    <input type="radio" name="saved-dge" checked={selectedSaved === i}
                      onChange={() => setSelectedSaved(i)} className="mt-0.5 accent-indigo-600" />
                    <div>
                      <div className="text-sm font-medium text-slate-700">
                        {r.source_label} — {r.group_by}: {r.ident1 || '(all)'} vs {r.ident2 || 'others'}
                      </div>
                      <div className="text-xs text-slate-400 mt-0.5">
                        {r.n_markers.toLocaleString()} genes ({r.n_significant.toLocaleString()} significant) ·
                        {' '}{r.assay}/{r.slot} · {r.test_use} · {new Date(r.created_at).toLocaleString()}
                      </div>
                    </div>
                  </label>
                ))}
              </div>
            )}
          </div>
        ) : csvInput === 'paste' ? (
          <textarea value={pastedGenes} onChange={e => setPastedGenes(e.target.value)}
            rows={6} placeholder={"gene,pval,logFC,padj\nCD3E,0.001,2.1,0.01\nFOXP3,0.005,-1.3,0.04"}
            className="w-full border border-slate-300 rounded px-3 py-2 text-xs font-mono focus:outline-none focus:ring-1 focus:ring-indigo-400" />
        ) : (
          <div>
            <input type="file" accept=".csv,.txt" onChange={e => setUploadedFile(e.target.files?.[0] ?? null)}
              className="text-sm text-slate-600" />
            {uploadedFile && <span className="text-xs text-slate-400 ml-2">{uploadedFile.name}</span>}
          </div>
        )}

        <div className="flex items-center gap-3">
          <button onClick={handleRun} disabled={status === 'running'}
            className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-medium rounded-lg disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
            {status === 'running' ? 'Running… (polling every 5 s)' : 'Run Pathway Analysis'}
          </button>
          {status === 'running' && taskId && (
            <button onClick={async () => {
              try { await cancelPathwayAnalysis(taskId) } catch {}
              clearInterval(pollRef.current!)
              setStatus('idle')
              setLog(prev => prev + '\n[Cancelled by user]')
            }}
              className="px-4 py-2 border border-red-300 text-red-600 text-sm font-medium rounded-lg hover:bg-red-50 transition-colors">
              Cancel
            </button>
          )}
        </div>

        {(status === 'running' || status === 'done' || (status === 'error' && log)) && (
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <span className="text-xs font-medium text-slate-600">R log</span>
              {status === 'running' && (
                <span className="text-xs text-amber-600 animate-pulse">● running…</span>
              )}
              {status === 'done' && <span className="text-xs text-green-600">✓ done</span>}
              {status === 'error' && <span className="text-xs text-red-600">✗ error</span>}
            </div>
            <pre ref={logRef}
              className="text-xs font-mono bg-slate-900 text-slate-100 rounded-lg p-3 overflow-auto max-h-48 whitespace-pre-wrap leading-relaxed">
              {log || '(waiting for output…)'}
            </pre>
          </div>
        )}
        {status === 'error' && error && !log && (
          <p className="text-xs text-red-600 bg-red-50 rounded p-2 font-mono whitespace-pre-wrap">{error}</p>
        )}
      </div>

      {/* Results */}
      {status === 'done' && results && (
        <div className="bg-white rounded-xl border border-slate-200 p-4 space-y-3">
          <h3 className="font-semibold text-slate-700">Results</h3>

          {/* Method selector */}
          <div className="flex flex-wrap gap-1">
            {methods.map(m => (
              <button key={m} onClick={() => setActiveMethod(m)}
                className={`px-3 py-1 rounded-full text-xs font-medium transition-colors
                  ${activeMethod === m ? 'bg-indigo-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>
                {pathwayLabel(m)}
              </button>
            ))}
          </div>

          {activeMethod && results[activeMethod] && (
            <div className="space-y-4">
              <PathwayMethodExplanation methodKey={activeMethod} rows={results[activeMethod]} />
              <PathwayDotplot rows={results[activeMethod]} label={pathwayLabel(activeMethod)} />
              <PathwayResultTable rows={results[activeMethod]} label={pathwayLabel(activeMethod)} />
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// ── CellChat tab ───────────────────────────────────────────────────────────────
function CellChatTab({ meta, sessionId }: { meta: SeuratMeta; sessionId: string }) {
  const reductions = Object.keys(meta.reductions)
  const clusterCols = Object.keys(meta.metadata)

  const [sampleId,       setSampleId]       = useState('ALL')
  const [filter10cells,  setFilter10cells]  = useState('NoFilter')
  const [reductionName,  setReductionName]  = useState(reductions[0] ?? 'umap')
  const [clusterName,    setClusterName]    = useState(clusterCols[0] ?? 'seurat_clusters')
  const detectedSpec = useMemo(() => {
    const sample = (meta.genes ?? []).slice(0, 200).filter((g: string) => g.length >= 3)
    if (!sample.length) return 'Human'
    const pctUpper = sample.filter((g: string) => g === g.toUpperCase()).length / sample.length
    return pctUpper > 0.5 ? 'Human' : 'Mouse'
  }, [meta.genes])
  const [inputSpec, setInputSpec] = useState(detectedSpec)
  const [taskId,         setTaskId]         = useState<string | null>(null)
  const [status,         setStatus]         = useState<'idle' | 'running' | 'done' | 'error'>('idle')
  const [reportUrl,      setReportUrl]      = useState<string | null>(null)
  const [error,          setError]          = useState<string | null>(null)
  const [log,            setLog]            = useState('')
  const logRef = useRef<HTMLPreElement>(null)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight
  }, [log])

  useEffect(() => {
    if (!taskId || status !== 'running') return
    pollRef.current = setInterval(async () => {
      try {
        const res = await getCellChatStatus(taskId)
        if (res.log) setLog(res.log)
        if (res.status === 'done') {
          clearInterval(pollRef.current!)
          setStatus('done')
          setReportUrl(res.report_url ?? null)
        } else if (res.status === 'error') {
          clearInterval(pollRef.current!)
          setStatus('error')
          setError(res.error ?? 'Unknown error')
        } else if ((res.status as string) === 'cancelled') {
          clearInterval(pollRef.current!)
          setStatus('idle')
        }
      } catch {}
    }, 8000)
    return () => { if (pollRef.current) clearInterval(pollRef.current) }
  }, [taskId, status])

  async function handleRun() {
    setStatus('running')
    setReportUrl(null)
    setError(null)
    setLog('')
    try {
      const { task_id } = await startCellChat({
        session_id: sessionId,
        sample_id: sampleId || 'ALL',
        filter10cells,
        reduction_name: reductionName,
        cluster_name: clusterName,
        input_spec: inputSpec,
      })
      setTaskId(task_id)
      toast.success('CellChat analysis started — this may take 15–60 minutes')
    } catch (e: any) {
      setStatus('error')
      setError(e.response?.data?.detail ?? String(e))
    }
  }

  return (
    <div className="p-4 space-y-4">
      <div className="bg-white rounded-xl border border-slate-200 p-4 space-y-4">
        <h3 className="font-semibold text-slate-700">CellChat Analysis</h3>
        <p className="text-xs text-slate-400">
          Runs CellChat cell-cell communication analysis on the loaded Seurat object and renders an HTML report.
          Results are cached — re-running with the same parameters is fast.
        </p>

        <div className="grid grid-cols-2 gap-4 md:grid-cols-3">
          <div>
            <label className="text-xs text-slate-500 block mb-1">Sample ID <span className="text-slate-400">(leave "ALL" to use all cells)</span></label>
            <input value={sampleId} onChange={e => setSampleId(e.target.value)}
              placeholder="ALL"
              className="border border-slate-300 rounded px-3 py-1.5 text-sm w-full focus:outline-none focus:ring-1 focus:ring-indigo-400" />
          </div>

          <div>
            <label className="text-xs text-slate-500 block mb-1">Filter &lt;10 cells per cluster</label>
            <select value={filter10cells} onChange={e => setFilter10cells(e.target.value)}
              className="border border-slate-300 rounded px-3 py-1.5 text-sm w-full">
              <option value="NoFilter">No filter</option>
              <option value="Filter10">Filter (&lt;10 cells)</option>
            </select>
          </div>

          <div>
            <label className="text-xs text-slate-500 block mb-1">
              Species
              <span className="ml-1 text-slate-400 font-normal">(auto-detected: {detectedSpec})</span>
            </label>
            <select value={inputSpec} onChange={e => setInputSpec(e.target.value)}
              className="border border-slate-300 rounded px-3 py-1.5 text-sm w-full">
              <option value="Human">Human</option>
              <option value="Mouse">Mouse</option>
            </select>
          </div>

          <div>
            <label className="text-xs text-slate-500 block mb-1">Reduction (UMAP)</label>
            <select value={reductionName} onChange={e => setReductionName(e.target.value)}
              className="border border-slate-300 rounded px-3 py-1.5 text-sm w-full">
              {reductions.map(r => <option key={r} value={r}>{r}</option>)}
            </select>
          </div>

          <div>
            <label className="text-xs text-slate-500 block mb-1">Cluster column</label>
            <select value={clusterName} onChange={e => setClusterName(e.target.value)}
              className="border border-slate-300 rounded px-3 py-1.5 text-sm w-full">
              {clusterCols.map(c => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button onClick={handleRun} disabled={status === 'running'}
            className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 text-white text-sm font-medium rounded-lg disabled:opacity-50 disabled:cursor-not-allowed transition-colors">
            {status === 'running' ? 'Running… (polling every 8 s)' : 'Run CellChat Analysis'}
          </button>
          {status === 'running' && taskId && (
            <button onClick={async () => {
              try { await cancelCellChat(taskId) } catch {}
              clearInterval(pollRef.current!)
              setStatus('idle')
              setLog(prev => prev + '\n[Cancelled by user]')
            }}
              className="px-4 py-2 border border-red-300 text-red-600 text-sm font-medium rounded-lg hover:bg-red-50 transition-colors">
              Cancel
            </button>
          )}
        </div>

        {(status === 'running' || status === 'done' || (status === 'error' && log)) && (
          <div className="space-y-1">
            <div className="flex items-center gap-2">
              <span className="text-xs font-medium text-slate-600">R log</span>
              {status === 'running' && (
                <span className="text-xs text-amber-600 animate-pulse">● running</span>
              )}
              {status === 'done' && <span className="text-xs text-green-600">✓ done</span>}
              {status === 'error' && <span className="text-xs text-red-600">✗ error</span>}
            </div>
            <pre ref={logRef}
              className="bg-slate-900 text-green-300 text-xs rounded-lg p-3 overflow-auto max-h-64 font-mono whitespace-pre-wrap">
              {log || '(waiting for output…)'}
            </pre>
          </div>
        )}
        {status === 'error' && error && !log && (
          <p className="text-xs text-red-600 bg-red-50 rounded p-2 font-mono whitespace-pre-wrap">{error}</p>
        )}
      </div>

      {status === 'done' && reportUrl && (
        <div className="flex items-center gap-3 p-4 bg-green-50 border border-green-200 rounded-xl">
          <span className="text-sm text-green-700 font-medium">✓ CellChat report ready</span>
          <a href={reportUrl} download="CellChat_report.html"
            className="px-3 py-1.5 text-xs border border-slate-300 rounded hover:bg-slate-100 text-slate-600">
            ↓ Download HTML
          </a>
          <a href={reportUrl} target="_blank" rel="noopener noreferrer"
            className="px-3 py-1.5 text-xs bg-indigo-600 hover:bg-indigo-700 text-white rounded">
            Open in new tab ↗
          </a>
        </div>
      )}
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
    const tid = toast.loading('Loading saved data… this may take a minute')
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

// ── Guide Tab ─────────────────────────────────────────────────────────────────
function GuideTab() {
  const sections = [
    {
      tab: 'UMAP',
      icon: '🔵',
      summary: 'Visualise all cells in 2-D reduced space, coloured by any metadata column.',
      details: [
        { label: 'Reduction', text: 'Choose the dimensionality reduction to display (UMAP, tSNE, PCA, …) from the sidebar.' },
        { label: 'Colour by', text: 'Select any metadata column — cluster identity, sample, cell type, etc. — to colour cells.' },
        { label: 'Split by', text: 'Optionally split the plot into one panel per category of a second metadata column.' },
        { label: 'Subset clusters', text: 'Check/uncheck cluster labels in the sidebar to focus the plot on specific populations.' },
      ],
    },
    {
      tab: 'Feature Plot',
      icon: '🧬',
      summary: 'Overlay gene expression onto the UMAP — one panel per gene, coloured by expression level.',
      details: [
        { label: 'Genes', text: 'Type one or more comma-separated gene names (e.g. CD3E, CD8A). Expression is fetched from the selected assay and slot.' },
        { label: 'Assay / slot', text: 'Set in the sidebar. "data" (log-normalised) is the default; "counts" gives raw counts.' },
        { label: 'Subset', text: 'Only cells in the selected cluster subset are shown.' },
        { label: 'Download PDF', text: 'Exports all gene panels tiled onto a single vector PDF page (like ggsave() in R) — paths stay fully editable when opened in Illustrator, unlike a flattened screenshot.' },
      ],
    },
    {
      tab: 'Violin Plot',
      icon: '🎻',
      summary: 'Show the distribution of gene expression across clusters as violin/jitter plots.',
      details: [
        { label: 'Genes', text: 'Comma-separated gene names — one violin group per gene per cluster.' },
        { label: 'Colour by', text: 'Controls which metadata column defines the x-axis grouping.' },
        { label: 'Subset', text: 'Restricts which clusters appear on the x-axis.' },
        { label: 'Download PDF', text: 'Exports all gene panels tiled onto a single vector PDF page (like ggsave() in R) — paths stay fully editable when opened in Illustrator, unlike a flattened screenshot.' },
      ],
    },
    {
      tab: 'Box Plot',
      icon: '📦',
      summary: 'Show the distribution of gene expression across clusters as box plots (median, quartiles, outliers) — the same data as Violin Plot, in box-and-whisker form.',
      details: [
        { label: 'Genes', text: 'Comma-separated gene names — one box per gene per cluster.' },
        { label: 'Colour by', text: 'Controls which metadata column defines the x-axis grouping.' },
        { label: 'Subset', text: 'Restricts which clusters appear on the x-axis.' },
        { label: 'Download PDF', text: 'Exports all gene panels tiled onto a single vector PDF page (like ggsave() in R) — paths stay fully editable when opened in Illustrator, unlike a flattened screenshot.' },
      ],
    },
    {
      tab: 'DGE — Clusters',
      icon: '📊',
      summary: 'Run FindAllMarkers to find marker genes for every cluster versus all other clusters.',
      details: [
        { label: 'Group by', text: 'The metadata column that defines clusters (usually seurat_clusters).' },
        { label: 'Statistical test', text: 'wilcox (default), t, LR, or negbinom — each with different assumptions.' },
        { label: 'p-val / logFC thresholds', text: 'Filter results shown in the table; the underlying test uses all genes.' },
        { label: 'Remove TCR/BCR genes', text: 'Strips TRAV/TRBV/IGHV/IGLV gene families to avoid V(D)J noise.' },
        { label: 'Cached results', text: 'Every combination of assay, slot, group-by, test, and TCR/BCR removal is cached against this Seurat object. The "Cached results" panel shows what has already been run (with p-val/logFC thresholds used) — click Load to view the volcano plot and gene table instantly without re-running, or Delete to free up storage. Re-running with identical settings also returns the cached result instead of recomputing. Note: unlike DGE — Conditions, results here are not offered to the Pathway tab (which expects a single two-group comparison, not one-vs-rest per cluster).' },
      ],
    },
    {
      tab: 'DGE — Conditions',
      icon: '⚖️',
      summary: 'Run FindMarkers between two user-defined groups within a metadata column.',
      details: [
        { label: 'Group by', text: 'Metadata column that separates conditions (e.g. sample, treatment).' },
        { label: 'Group 1 / Group 2', text: 'Comma-separated values for each side of the comparison (e.g. "ctrl,ctrl2" vs "treated"). Commas within a field are handled correctly.' },
        { label: 'Volcano plot', text: 'After the run, a volcano plot shows –log10(p-adj) vs log2FC; click points to highlight genes.' },
        { label: 'Save results', text: 'Results are automatically offered to the Pathway tab.' },
        { label: 'Cached results', text: 'Every combination of assay, slot, group column, Group 1/2, test, and TCR/BCR removal is cached against this Seurat object. The "Cached results" panel shows what has already been run — click Load to view the volcano plot and gene table instantly without re-running, or Delete to free up storage.' },
      ],
    },
    {
      tab: 'Pathway',
      icon: '🛣️',
      summary: 'Run Over-Representation Analysis (ORA) and Gene Set Enrichment Analysis (GSEA) across GO, KEGG, WikiPathways, and MSigDB.',
      details: [
        { label: 'Gene list source', text: 'Three modes — "From DGE" auto-populates from a saved DGE — Conditions run (DGE — Clusters results aren\'t offered here, since pathway analysis expects a single ranked two-group comparison); "Paste" accepts a raw gene list; "Upload CSV" accepts a file with gene, logFC, pval, padj columns.' },
        { label: 'Species', text: 'Auto-detected from gene name capitalisation (>50 % uppercase → human / hsa). Override to hsa or mmu if needed.' },
        { label: 'p-value cutoff', text: 'Applied to all ORA and GSEA results (default 0.05).' },
        { label: 'Methods run', text: 'GO BP/MF/CC (up/down/all), KEGG, WikiPathways, and all MSigDB collections (H + C1–C9 for human, H + M1–M8 for mouse) — both ORA and GSEA per collection.' },
        { label: 'Live log', text: 'A terminal panel shows R output in real time so you can track progress.' },
        { label: 'Results', text: 'Each method appears as a collapsible section with a paginated table of enriched terms.' },
      ],
    },
    {
      tab: 'CellChat',
      icon: '💬',
      summary: 'Infer cell-cell communication networks and render an interactive HTML report.',
      details: [
        { label: 'Sample', text: '"ALL" uses every cell; enter a value from the "label" metadata column to analyse a subset.' },
        { label: 'Cell filter', text: '"Filter10" removes cell populations with fewer than 10 cells before inference.' },
        { label: 'Reduction / Cluster column', text: 'Must match the reduction and cluster metadata column actually present in the object.' },
        { label: 'Species', text: 'Human or Mouse — selects the matching CellChat ligand-receptor database.' },
        { label: 'Caching', text: 'The CellChat object is saved as an .rds file; re-running with the same parameters reloads it instantly.' },
        { label: 'Report', text: 'The rendered HTML report opens inside an iframe. It contains UMAP overviews, interaction count/weight matrices, circle plots, heatmaps, and per-pathway signal views.' },
      ],
    },
    {
      tab: 'Metadata',
      icon: '📋',
      summary: 'Browse and filter the full per-cell metadata table from the Seurat object.',
      details: [
        { label: 'Filter', text: 'Type in any column header search box to filter rows by value.' },
        { label: 'Sort', text: 'Click any column header to sort ascending (▲) or descending (▼).' },
        { label: 'Rows shown', text: 'Up to 500 cells are displayed for performance; apply filters to narrow the view.' },
      ],
    },
  ]

  return (
    <div className="p-6 max-w-3xl mx-auto space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-slate-800 mb-1">Explore — user guide</h2>
        <p className="text-sm text-slate-500">
          Load a Seurat <code className="bg-slate-100 px-1 rounded">.rds</code> file from the upload screen to unlock all tabs below.
          The sidebar controls (reduction, colour-by, assay, slot, split-by, cluster subset) apply globally to the visualisation tabs.
        </p>
      </div>

      {sections.map(({ tab, icon, summary, details }) => (
        <div key={tab} className="bg-white rounded-lg border border-slate-200 overflow-hidden">
          <div className="px-4 py-3 border-b border-slate-100 flex items-center gap-2">
            <span className="text-base">{icon}</span>
            <span className="font-medium text-slate-800 text-sm">{tab}</span>
          </div>
          <div className="px-4 py-3 space-y-3">
            <p className="text-sm text-slate-600">{summary}</p>
            <dl className="space-y-1.5">
              {details.map(({ label, text }) => (
                <div key={label} className="flex gap-2 text-sm">
                  <dt className="font-medium text-slate-700 shrink-0 w-40">{label}</dt>
                  <dd className="text-slate-500">{text}</dd>
                </div>
              ))}
            </dl>
          </div>
        </div>
      ))}

      <div className="bg-indigo-50 border border-indigo-100 rounded-lg px-4 py-3 text-sm text-indigo-700 space-y-1">
        <p className="font-medium">Tips</p>
        <ul className="list-disc list-inside space-y-0.5 text-indigo-600">
          <li>DGE — Conditions results are automatically offered to the Pathway tab — no copy-paste needed.</li>
          <li>Pathway analysis and CellChat run as background jobs; you can switch tabs while they compute.</li>
          <li>DGE and CellChat both cache their output — re-running with the same settings is instant, and cached DGE runs are visible in the "Cached results" panel as soon as the Seurat object is loaded, even from previous sessions on the same file.</li>
          <li>Species is auto-detected from gene name case; override it if auto-detection picks the wrong organism.</li>
        </ul>
      </div>
    </div>
  )
}

// ── Main page ──────────────────────────────────────────────────────────────────
const TABS = ['UMAP', 'Feature Plot', 'Violin Plot', 'Box Plot', 'DGE — Clusters', 'DGE — Conditions', 'Pathway', 'CellChat', 'Metadata', 'Guide']

export default function ExplorePage() {
  const [meta,     setMeta]     = useState<SeuratMeta | null>(null)
  const [tab,      setTab]      = useState('UMAP')
  const [reduction, setReduction] = useState('')
  const [colorBy,  setColorBy]  = useState('')
  const [assay,    setAssay]    = useState('RNA')
  const [slot,     setSlot]     = useState('data')
  const [splitBy,  setSplitBy]  = useState('')
  const [selectedClusters, setSelectedClusters] = useState<string[]>([])
  // Bumped whenever a DGE run/load/delete happens, so PathwayTab knows to refetch its
  // cached-results list from the backend (which is the source of truth, not local state).
  const [dgeVersion, setDgeVersion] = useState(0)
  const [cacheStatus, setCacheStatus] = useState<'building' | 'ready' | 'idle'>('idle')
  const cachePollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  async function startCachePolling(sessionId: string, currentAssay: string, currentSlot: string) {
    if (cachePollRef.current) clearInterval(cachePollRef.current)
    cachePollRef.current = null

    const check = async () => {
      const res = await getCacheStatus(sessionId, currentAssay, currentSlot)
      setCacheStatus(res.status === 'ready' ? 'ready' : res.status === 'building' ? 'building' : 'idle')
      return res.status
    }

    // Immediate check so already-cached pairs show "ready" without waiting 10 s
    let status: string
    try { status = await check() } catch { return }
    if (status === 'ready') return

    // Keep polling until ready or 20 min elapsed
    let polls = 0
    cachePollRef.current = setInterval(async () => {
      polls++
      try {
        const s = await check()
        if (s === 'ready' || polls > 120) {
          clearInterval(cachePollRef.current!)
          cachePollRef.current = null
        }
      } catch {
        clearInterval(cachePollRef.current!)
        cachePollRef.current = null
      }
    }, 10000)
  }

  // Restart polling whenever the active (assay, slot) pair or session changes
  const sessionId = meta?.session_id
  useEffect(() => {
    if (!sessionId) return
    startCachePolling(sessionId, assay, slot)
  }, [assay, slot, sessionId])

  function handleDgeChanged() {
    setDgeVersion(v => v + 1)
  }

  function handleLoad(m: SeuratMeta) {
    setMeta(m)
    const reds = Object.keys(m.reductions)
    setReduction(reds.find(r => r.includes('umap')) ?? reds[0] ?? '')
    const cols = Object.keys(m.metadata)
    setColorBy(cols.find(c => c === 'seurat_clusters') ?? cols[0] ?? '')
    const defaultAssay = m.assays.find(a => a === 'RNA') ?? m.assays[0] ?? 'RNA'
    setAssay(defaultAssay)
    const rawSlots = m.assay_slots?.[defaultAssay]
    const availableSlots: string[] = Array.isArray(rawSlots) ? rawSlots : rawSlots ? [rawSlots as string] : ['data']
    setSlot(availableSlots.includes('data') ? 'data' : availableSlots[0] ?? 'data')
    const clVals = [...new Set(Object.values(m.metadata)[0] ?? [])]
    setSelectedClusters(clVals as string[])
    // cache polling is started by the useEffect watching [assay, slot, sessionId]
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
          <div className="ml-auto flex items-center gap-3 px-3">
            {cacheStatus === 'building' && (
              <span className="flex items-center gap-1.5 text-xs text-amber-600">
                <svg className="animate-spin w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <circle cx="12" cy="12" r="10" strokeOpacity="0.25" />
                  <path d="M12 2a10 10 0 0 1 10 10" />
                </svg>
                Building expression cache…
              </span>
            )}
            {cacheStatus === 'ready' && (
              <span className="text-xs text-green-600 flex items-center gap-1">
                <svg className="w-3 h-3" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clipRule="evenodd" /></svg>
                Gene cache ready
              </span>
            )}
            <button onClick={() => {
              if (cachePollRef.current) clearInterval(cachePollRef.current)
              setCacheStatus('idle')
              setMeta(null)
              setTab('UMAP')
            }}
              className="text-xs text-slate-400 hover:text-slate-600">
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
            <DistributionPlotTab meta={meta} assay={assay} slot={slot}
              selectedClusters={selectedClusters} colorBy={colorBy} sessionId={meta.session_id} plotType="violin" />
          </div>
          <div className={tab === 'Box Plot' ? '' : 'hidden'}>
            <DistributionPlotTab meta={meta} assay={assay} slot={slot}
              selectedClusters={selectedClusters} colorBy={colorBy} sessionId={meta.session_id} plotType="box" />
          </div>
          <div className={tab === 'DGE — Clusters' ? '' : 'hidden'}>
            <DGETab meta={meta} assay={assay} slot={slot} colorBy={colorBy}
              sessionId={meta.session_id} mode="clusters" onDgeChanged={handleDgeChanged} />
          </div>
          <div className={tab === 'DGE — Conditions' ? '' : 'hidden'}>
            <DGETab meta={meta} assay={assay} slot={slot} colorBy={colorBy}
              sessionId={meta.session_id} mode="conditions" onDgeChanged={handleDgeChanged} />
          </div>
          <div className={tab === 'Pathway' ? '' : 'hidden'}>
            <PathwayTab meta={meta} sessionId={meta.session_id} dgeVersion={dgeVersion} />
          </div>
          <div className={tab === 'CellChat' ? '' : 'hidden'}>
            <CellChatTab meta={meta} sessionId={meta.session_id} />
          </div>
          <div className={tab === 'Metadata' ? '' : 'hidden'}>
            <MetadataTab meta={meta} />
          </div>
          <div className={tab === 'Guide' ? '' : 'hidden'}>
            <GuideTab />
          </div>
        </div>
      </div>
    </div>
  )
}
