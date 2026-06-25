suppressPackageStartupMessages({
  library(shiny)
  library(Seurat)
  library(ggplot2)
  library(dplyr)
  library(DT)
  library(shinycssloaders)
})

# ── UI ─────────────────────────────────────────────────────────────────────────
ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      body { font-family: 'Inter', sans-serif; background: #f8fafc; }
      .sidebar-panel { background: #fff; border-right: 1px solid #e2e8f0; padding: 16px; min-height: 100vh; }
      .main-panel { padding: 16px; }
      .section-title { font-size: 11px; font-weight: 600; color: #64748b; text-transform: uppercase;
                       letter-spacing: 0.05em; margin: 16px 0 6px; }
      hr { border-color: #e2e8f0; margin: 12px 0; }
      .upload-box { border: 2px dashed #c7d2fe; border-radius: 8px; padding: 20px;
                    text-align: center; background: #f0f4ff; margin-bottom: 12px; }
    "))
  ),

  titlePanel(NULL),

  sidebarLayout(
    sidebarPanel(width = 3, class = "sidebar-panel",
      div(class = "upload-box",
        fileInput("rds_file", NULL, accept = ".rds",
                  placeholder = "Upload Seurat .rds", buttonLabel = "Browse…")
      ),

      conditionalPanel("output.object_loaded",
        div(class = "section-title", "Object info"),
        verbatimTextOutput("obj_summary", placeholder = TRUE),

        hr(),
        div(class = "section-title", "Reduction"),
        uiOutput("ui_reduction"),

        div(class = "section-title", "Colour / Group by"),
        uiOutput("ui_color_by"),

        div(class = "section-title", "Assay"),
        uiOutput("ui_assay"),

        div(class = "section-title", "Data slot"),
        uiOutput("ui_data_slot"),

        hr(),
        div(class = "section-title", "Gene(s) — comma-separated"),
        textInput("genes", NULL, value = "", placeholder = "e.g. Cd3e, Cd8a"),

        div(class = "section-title", "Subset clusters"),
        uiOutput("ui_cluster_subset"),

        div(class = "section-title", "Split by"),
        uiOutput("ui_split_by")
      )
    ),

    mainPanel(width = 9, class = "main-panel",
      conditionalPanel("!output.object_loaded",
        div(style = "text-align:center; padding: 80px; color: #94a3b8;",
          h3("Upload a Seurat .rds file to start exploring"),
          p("Supports Seurat v4 and v5 objects")
        )
      ),
      conditionalPanel("output.object_loaded",
        tabsetPanel(id = "main_tabs",
          # ── UMAP ──────────────────────────────────────────────────────────
          tabPanel("UMAP",
            br(),
            fluidRow(
              column(6, withSpinner(plotOutput("umap_plot", height = "550px"))),
              column(6, withSpinner(plotOutput("umap_split_plot", height = "550px")))
            ),
            br(),
            downloadButton("dl_umap_pdf", "PDF"), downloadButton("dl_umap_svg", "SVG")
          ),

          # ── Feature Plot ──────────────────────────────────────────────────
          tabPanel("Feature Plot",
            br(),
            withSpinner(plotOutput("feature_plot", height = "600px")),
            br(),
            downloadButton("dl_feature_pdf", "PDF"), downloadButton("dl_feature_svg", "SVG")
          ),

          # ── Violin Plot ───────────────────────────────────────────────────
          tabPanel("Violin Plot",
            br(),
            withSpinner(plotOutput("violin_plot", height = "500px")),
            br(),
            downloadButton("dl_violin_pdf", "PDF"), downloadButton("dl_violin_svg", "SVG")
          ),

          # ── DGE — Clusters ────────────────────────────────────────────────
          tabPanel("DGE — Clusters",
            br(),
            wellPanel(
              fluidRow(
                column(3, selectInput("dge_test", "Test", c("wilcox","t","MAST","DESeq2"), "wilcox")),
                column(3, numericInput("dge_pval",  "adj. p-val ≤", 0.05, 0, 1, 0.01)),
                column(3, numericInput("dge_logfc", "|log2FC| ≥",   0.25, 0, 10, 0.05)),
                column(3,
                  br(),
                  checkboxInput("dge_rm_tcr", "Remove TCR genes", TRUE),
                  checkboxInput("dge_rm_bcr", "Remove BCR genes", TRUE)
                )
              ),
              actionButton("run_dge", "Run FindAllMarkers", class = "btn-primary")
            ),
            verbatimTextOutput("dge_log"),
            uiOutput("dge_tables_ui"),
            uiOutput("dge_feature_ui")
          ),

          # ── DGE — Conditions ──────────────────────────────────────────────
          tabPanel("DGE — Conditions",
            br(),
            wellPanel(
              fluidRow(
                column(4, uiOutput("ui_condition_col")),
                column(4, uiOutput("ui_cond_group1")),
                column(4, uiOutput("ui_cond_group2"))
              ),
              fluidRow(
                column(3, selectInput("cond_test", "Test", c("wilcox","t","MAST","DESeq2"), "wilcox")),
                column(3, numericInput("cond_pval",  "adj. p-val ≤", 0.05, 0, 1, 0.01)),
                column(3, numericInput("cond_logfc", "|log2FC| ≥",   0.25, 0, 10, 0.05)),
                column(3, br(), actionButton("run_cond_dge", "Run FindMarkers", class = "btn-primary"))
              )
            ),
            verbatimTextOutput("cond_dge_log"),
            DT::dataTableOutput("cond_dge_table")
          ),

          # ── Metadata Table ────────────────────────────────────────────────
          tabPanel("Metadata",
            br(),
            DT::dataTableOutput("meta_table")
          )
        )
      )
    )
  )
)

# ── Server ─────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  # ── Load object ─────────────────────────────────────────────────────────────
  s.obj <- reactive({
    req(input$rds_file)
    withProgress(message = "Loading RDS…", readRDS(input$rds_file$datapath))
  })

  output$object_loaded <- reactive({ !is.null(s.obj()) })
  outputOptions(output, "object_loaded", suspendWhenHidden = FALSE)

  output$obj_summary <- renderText({
    o <- s.obj()
    sprintf("Cells: %d\nFeatures: %d\nAssays: %s\nReductions: %s",
            ncol(o), nrow(o),
            paste(names(o@assays), collapse = ", "),
            paste(names(o@reductions), collapse = ", "))
  })

  # ── Dynamic UI ──────────────────────────────────────────────────────────────
  output$ui_reduction <- renderUI({
    reds <- names(s.obj()@reductions)
    sel  <- if ("umap.unintegrated" %in% reds) "umap.unintegrated" else reds[1]
    selectInput("reduction", NULL, reds, sel)
  })
  output$ui_color_by <- renderUI({
    cols <- colnames(s.obj()@meta.data)
    sel  <- if ("seurat_clusters" %in% cols) "seurat_clusters" else cols[1]
    selectInput("color_by", NULL, cols, sel)
  })
  output$ui_assay <- renderUI({
    assays <- names(s.obj()@assays)
    sel <- if ("RNA" %in% assays) "RNA" else assays[1]
    selectInput("assay", NULL, assays, sel)
  })
  output$ui_data_slot <- renderUI({
    selectInput("data_slot", NULL, c("data","counts","scale.data"), "data")
  })
  output$ui_cluster_subset <- renderUI({
    o    <- s.obj()
    vals <- sort(unique(as.character(o@meta.data[[input$color_by]])))
    checkboxGroupInput("cluster_subset", NULL, vals, vals)
  })
  output$ui_split_by <- renderUI({
    cols <- c("none", colnames(s.obj()@meta.data))
    selectInput("split_by", NULL, cols, "none")
  })
  output$ui_condition_col <- renderUI({
    cols <- colnames(s.obj()@meta.data)
    selectInput("condition_col", "Condition column", cols, cols[1])
  })
  output$ui_cond_group1 <- renderUI({
    req(input$condition_col)
    vals <- sort(unique(as.character(s.obj()@meta.data[[input$condition_col]])))
    selectInput("cond_g1", "Group 1 (ident.1)", vals, vals[1])
  })
  output$ui_cond_group2 <- renderUI({
    req(input$condition_col)
    vals <- sort(unique(as.character(s.obj()@meta.data[[input$condition_col]])))
    selectInput("cond_g2", "Group 2 (ident.2)", vals, if (length(vals) > 1) vals[2] else vals[1])
  })

  # ── Processed object (subset + ident) ───────────────────────────────────────
  s.processed <- reactive({
    o <- s.obj()
    req(input$color_by, input$assay, input$cluster_subset)
    DefaultAssay(o) <- input$assay
    Idents(o)       <- input$color_by
    keep <- rownames(o@meta.data)[as.character(o@meta.data[[input$color_by]]) %in% input$cluster_subset]
    if (length(keep) < ncol(o)) o <- subset(o, cells = keep)
    o
  })

  parse_genes <- reactive({
    req(input$genes)
    g <- trimws(unlist(strsplit(input$genes, ",")))
    g[nchar(g) > 0]
  })

  # ── UMAP ────────────────────────────────────────────────────────────────────
  umap_obj <- reactive({
    req(input$reduction, input$color_by)
    DimPlot(s.processed(), reduction = input$reduction, group.by = input$color_by,
            label = TRUE, label.box = TRUE) +
      theme(aspect.ratio = 1) + ggtitle("UMAP")
  })
  umap_split_obj <- reactive({
    req(input$reduction, input$color_by, input$split_by)
    if (input$split_by == "none") return(NULL)
    DimPlot(s.processed(), reduction = input$reduction, group.by = input$color_by,
            split.by = input$split_by, label = TRUE) +
      theme(aspect.ratio = 1) + ggtitle(paste("Split by", input$split_by))
  })
  output$umap_plot       <- renderPlot(res = 100, { umap_obj() })
  output$umap_split_plot <- renderPlot(res = 100, { req(umap_split_obj()); umap_split_obj() })
  output$dl_umap_pdf <- downloadHandler("umap.pdf",
    function(f) ggsave(f, umap_obj(), "pdf", width=10, height=10, dpi=300))
  output$dl_umap_svg <- downloadHandler("umap.svg",
    function(f) ggsave(f, umap_obj(), "svg", width=10, height=10, dpi=300))

  # ── Feature Plot ─────────────────────────────────────────────────────────────
  feature_obj <- reactive({
    genes <- parse_genes()
    req(length(genes) > 0)
    sp <- if (input$split_by == "none") NULL else input$split_by
    ncols <- if (length(genes) > 1) 3 else NULL
    FeaturePlot(s.processed(), reduction = input$reduction, features = genes,
                slot = input$data_slot, label = TRUE, order = TRUE,
                ncol = ncols, split.by = sp) +
      theme(aspect.ratio = 1)
  })
  output$feature_plot    <- renderPlot(res = 100, { feature_obj() })
  output$dl_feature_pdf  <- downloadHandler(
    function() paste0(gsub(",", "_", input$genes), "_feature.pdf"),
    function(f) ggsave(f, feature_obj(), "pdf", width=12, height=12, dpi=300))
  output$dl_feature_svg  <- downloadHandler(
    function() paste0(gsub(",", "_", input$genes), "_feature.svg"),
    function(f) ggsave(f, feature_obj(), "svg", width=12, height=12, dpi=300))

  # ── Violin Plot ──────────────────────────────────────────────────────────────
  violin_obj <- reactive({
    genes <- parse_genes()
    req(length(genes) > 0)
    sp <- if (input$split_by == "none") NULL else input$split_by
    ncols <- if (length(genes) > 1) 3 else NULL
    VlnPlot(s.processed(), features = genes, slot = input$data_slot,
            pt.size = 0, ncol = ncols, split.by = sp)
  })
  output$violin_plot    <- renderPlot(res = 100, { violin_obj() })
  output$dl_violin_pdf  <- downloadHandler(
    function() paste0(gsub(",", "_", input$genes), "_violin.pdf"),
    function(f) ggsave(f, violin_obj(), "pdf", width=12, height=8, dpi=300))
  output$dl_violin_svg  <- downloadHandler(
    function() paste0(gsub(",", "_", input$genes), "_violin.svg"),
    function(f) ggsave(f, violin_obj(), "svg", width=12, height=8, dpi=300))

  # ── DGE — Clusters ───────────────────────────────────────────────────────────
  TCR_PATTERNS <- c("Trav","Traj","Trac","Trbv","Trbd","Trbj","Trbc",
                    "Trgv","Trgj","Trgc","Trdv","Trdc","Trdj")
  BCR_PATTERNS <- c("Ighv","Ighd","Ighj","Ighc","Igkv","Igkj","Igkc","Iglv","Iglj","Iglc")

  exclude_genes <- function(all_genes) {
    ex <- character(0)
    if (isTRUE(input$dge_rm_tcr)) {
      pats <- c(TCR_PATTERNS, toupper(TCR_PATTERNS))
      ex <- c(ex, all_genes[substr(all_genes, 1, 4) %in% pats])
    }
    if (isTRUE(input$dge_rm_bcr)) {
      pats <- c(BCR_PATTERNS, toupper(BCR_PATTERNS))
      ex <- c(ex, all_genes[substr(all_genes, 1, 4) %in% pats])
    }
    unique(ex)
  }

  dge_log    <- reactiveVal("Click 'Run FindAllMarkers' to start.")
  dge_result <- reactiveVal(NULL)

  observeEvent(input$run_dge, {
    dge_log("Running FindAllMarkers…")
    dge_result(NULL)
    o      <- s.processed()
    ex     <- exclude_genes(rownames(o))
    feats  <- setdiff(rownames(o), ex)
    tryCatch({
      if (input$assay == "SCT") o <- PrepSCTFindMarkers(o)
      markers <- FindAllMarkers(o, assay = input$assay, group.by = input$color_by,
                                test.use = input$dge_test, slot = input$data_slot,
                                features = feats) %>%
        mutate(abs_avg_log2FC = abs(avg_log2FC))
      dge_result(markers)
      dge_log(sprintf("Done. %d markers found.", nrow(markers)))
    }, error = function(e) dge_log(paste("Error:", e$message)))
  })

  output$dge_log <- renderText({ dge_log() })

  dge_filtered <- reactive({
    req(dge_result())
    dge_result() %>%
      filter(p_val_adj <= input$dge_pval, abs_avg_log2FC >= input$dge_logfc)
  })

  output$dge_tables_ui <- renderUI({
    df <- dge_filtered()
    req(nrow(df) > 0)
    clusters <- sort(unique(df$cluster))
    tabs <- lapply(clusters, function(cl) {
      tabPanel(paste("Cluster", cl), DT::dataTableOutput(paste0("dge_tbl_", cl)))
    })
    do.call(tabsetPanel, tabs)
  })

  observe({
    df <- dge_filtered()
    req(nrow(df) > 0)
    for (cl in sort(unique(df$cluster))) {
      local({
        lcl <- cl
        output[[paste0("dge_tbl_", lcl)]] <- DT::renderDataTable({
          tmp <- df %>% filter(cluster == lcl) %>%
            select(gene, cluster, p_val, p_val_adj, avg_log2FC, abs_avg_log2FC, pct.1, pct.2) %>%
            arrange(desc(abs_avg_log2FC))
          DT::datatable(tmp, extensions = "Buttons",
            options = list(dom = "Blfrtip", buttons = c("copy","csv","excel"),
                           pageLength = 25), rownames = FALSE, filter = "top")
        }, server = FALSE)
      })
    }
  })

  output$dge_feature_ui <- renderUI({
    df <- dge_filtered()
    req(nrow(df) > 0)
    clusters <- sort(unique(df$cluster))
    tabs <- lapply(clusters, function(cl) {
      tabPanel(paste("Cluster", cl),
        plotOutput(paste0("dge_fp_", cl), height = "600px"),
        downloadButton(paste0("dl_dge_fp_", cl), "PDF"))
    })
    h4("Top 9 marker genes per cluster"), do.call(tabsetPanel, tabs)
  })

  observe({
    df <- dge_filtered()
    req(nrow(df) > 0)
    o <- s.processed()
    for (cl in sort(unique(df$cluster))) {
      local({
        lcl <- cl
        top_genes <- df %>% filter(cluster == lcl, avg_log2FC > 0) %>%
          arrange(desc(abs_avg_log2FC)) %>% head(9) %>% pull(gene)
        fp <- reactive({
          FeaturePlot(o, reduction = input$reduction, features = top_genes,
                      slot = input$data_slot, label = TRUE, order = TRUE, ncol = 3)
        })
        output[[paste0("dge_fp_", lcl)]] <- renderPlot(res = 100, { fp() })
        output[[paste0("dl_dge_fp_", lcl)]] <- downloadHandler(
          sprintf("FeaturePlot_cluster_%s.pdf", lcl),
          function(f) ggsave(f, fp(), "pdf", width=12, height=12, dpi=300))
      })
    }
  })

  # ── DGE — Conditions ─────────────────────────────────────────────────────────
  cond_log    <- reactiveVal("Select groups and click 'Run FindMarkers'.")
  cond_result <- reactiveVal(NULL)

  observeEvent(input$run_cond_dge, {
    req(input$condition_col, input$cond_g1, input$cond_g2)
    cond_log("Running FindMarkers…")
    cond_result(NULL)
    o <- s.obj()
    DefaultAssay(o) <- input$assay
    Idents(o) <- input$condition_col
    tryCatch({
      if (input$assay == "SCT") o <- PrepSCTFindMarkers(o)
      res <- FindMarkers(o, ident.1 = input$cond_g1, ident.2 = input$cond_g2,
                         test.use = input$cond_test, slot = input$data_slot) %>%
        tibble::rownames_to_column("gene") %>%
        mutate(abs_avg_log2FC = abs(avg_log2FC)) %>%
        filter(p_val_adj <= input$cond_pval, abs_avg_log2FC >= input$cond_logfc) %>%
        arrange(desc(abs_avg_log2FC))
      cond_result(res)
      cond_log(sprintf("Done. %d significant DEGs.", nrow(res)))
    }, error = function(e) cond_log(paste("Error:", e$message)))
  })

  output$cond_dge_log   <- renderText({ cond_log() })
  output$cond_dge_table <- DT::renderDataTable({
    req(cond_result())
    DT::datatable(cond_result(), extensions = "Buttons",
      options = list(dom = "Blfrtip", buttons = c("copy","csv","excel"),
                     pageLength = 25), rownames = FALSE, filter = "top")
  }, server = FALSE)

  # ── Metadata table ───────────────────────────────────────────────────────────
  output$meta_table <- DT::renderDataTable({
    meta <- s.obj()@meta.data %>% tibble::rownames_to_column("cell_barcode")
    DT::datatable(meta, extensions = "Buttons",
      options = list(dom = "Blfrtip", buttons = c("copy","csv","excel"),
                     pageLength = 25, scrollX = TRUE), rownames = FALSE, filter = "top")
  }, server = FALSE)
}

shinyApp(ui, server)
