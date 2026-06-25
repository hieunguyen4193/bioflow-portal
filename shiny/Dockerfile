FROM rocker/shiny:4.4.2

# System dependencies for Seurat
RUN apt-get update && apt-get install -y --no-install-recommends \
    libhdf5-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libgit2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libgeos-dev \
    && rm -rf /var/lib/apt/lists/*

# Install R packages
RUN Rscript -e "\
  options(repos = c(CRAN = 'https://cloud.r-project.org')); \
  pkgs <- c('Seurat','ggplot2','dplyr','DT','shinycssloaders','tibble'); \
  install.packages(pkgs, dependencies = TRUE)"

# Copy app
RUN rm -rf /srv/shiny-server/*
COPY app.R /srv/shiny-server/app.R

# Shiny server config: disable logging noise, set timeout
RUN echo 'run_as shiny;\n\
server {\n\
  listen 3838;\n\
  location / {\n\
    site_dir /srv/shiny-server;\n\
    log_dir /var/log/shiny-server;\n\
    directory_index on;\n\
  }\n\
}' > /etc/shiny-server/shiny-server.conf

EXPOSE 3838
CMD ["/usr/bin/shiny-server"]
