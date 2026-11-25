# R pipeline image: versioning and sharing

The backend runs each analysis in a short-lived container started from the R pipeline image (`pipeline-portal/r-pipeline:latest`, built from [`Dockerfile`](Dockerfile) and [`install_packages.R`](install_packages.R)). This page covers why rebuilding that image can change package versions, and how to share one fixed image through Docker Hub instead.

## The problem: rebuilds pick up new package versions

`deploy.sh` builds the image only when it's missing from the machine. On a new machine, or after the image is deleted, `install_packages.R` runs again and installs whatever versions are current at that moment. Two deployments built on different days can therefore run different package versions.

| Source | Where | Why it drifts |
|---|---|---|
| Base image | `FROM tronghieunguyen/single_cell_pipeline` | There's no tag, so it means `:latest`. A newly pushed base image changes R and Seurat. |
| CRAN | `install.packages(..., repos = "https://cloud.r-project.org")` | It always installs the current CRAN release. |
| Bioconductor | `BiocManager::install(...)` | The release is fixed by the R version, but packages still get patch updates within it. |
| CellChat | `install_github("jinworks/CellChat")` | It installs the latest commit on the default branch, which may include breaking changes. |

The `already()` checks in `install_packages.R` only skip packages that are already in the image being built. They don't help on a fresh machine.

## Fixes

1. **Build once, push, always pull (recommended).** Build the image a single time, push it with a version tag, and have every deployment pull that tag. Every machine then runs the same image, and the 15–30 minute build goes away.
2. **Pin versions in the build.** This makes a rebuild produce the same packages again, which matters when you add a package later:
   - Base image: `FROM tronghieunguyen/single_cell_pipeline:<tag>` (or `@sha256:<digest>`).
   - CRAN: use a dated Posit Package Manager snapshot, e.g. `repos = "https://packagemanager.posit.co/cran/2026-11-01"`.
   - Bioconductor: set `BiocManager::install(..., version = "3.xx")`.
   - CellChat: pin a commit, `install_github("jinworks/CellChat@<commit-sha>")`.

## Pushing the current image to Docker Hub

`deploy.sh` runs Docker with `sudo`, so the image is in root's Docker. Run these with `sudo` too:

```bash
# 1. Log in (use a Docker Hub access token as the password)
sudo docker login -u tronghieunguyen

# 2. Tag the existing image: a fixed version tag plus latest
sudo docker tag pipeline-portal/r-pipeline:latest tronghieunguyen/r-pipeline:2026.11
sudo docker tag pipeline-portal/r-pipeline:latest tronghieunguyen/r-pipeline:latest

# 3. Push both tags (the second push is near-instant; the layers are shared)
sudo docker push tronghieunguyen/r-pipeline:2026.11
sudo docker push tronghieunguyen/r-pipeline:latest
```

Before pushing:

- **The repository is public by default.** A repository created by pushing to it is public, and a free account gets only one private repository. To keep it private, create `r-pipeline` as private on hub.docker.com first.
- **The upload is large.** Layers already in the base image `tronghieunguyen/single_cell_pipeline` are skipped. Only the layers added by `install_packages.R` are uploaded.

Save the package versions in the pushed image as a reference:

```bash
sudo docker run --rm tronghieunguyen/r-pipeline:2026.11 \
  Rscript -e 'ip <- installed.packages()[, c("Package","Version")]; write.csv(ip, stdout(), row.names=FALSE)' \
  > pipeline-image/package-versions-2026.11.csv
```

## Using the pushed image on another machine

```bash
sudo docker pull tronghieunguyen/r-pipeline:2026.11
```

Then set `PIPELINE_IMAGE=tronghieunguyen/r-pipeline:2026.11` for the backend.

`deploy.sh` currently hard-codes `PIPELINE_IMAGE="pipeline-portal/r-pipeline:latest"` and doesn't export it, so Docker Compose uses its own default (also `pipeline-portal/r-pipeline:latest`). To use the pushed image, change that line to the versioned tag and export it, so that both the existence check in `deploy.sh` and the backend container use the same image.
