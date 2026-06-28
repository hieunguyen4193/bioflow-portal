FROM tronghieunguyen/single_cell_pipeline

# Install shiny server
RUN apt-get update && apt-get install -y --no-install-recommends gdebi-core wget \
    && wget -q https://download3.rstudio.org/ubuntu-18.04/x86_64/shiny-server-1.5.22.1017-amd64.deb \
    && gdebi -n shiny-server-1.5.22.1017-amd64.deb \
    && rm shiny-server-1.5.22.1017-amd64.deb \
    && rm -rf /var/lib/apt/lists/*

# Install any extra shiny-specific packages not already in the image
RUN Rscript -e "options(repos=c(CRAN='https://cloud.r-project.org')); \
    pkgs <- c('shiny','shinycssloaders','DT'); \
    pkgs <- pkgs[!pkgs %in% installed.packages()[,'Package']]; \
    if (length(pkgs)) install.packages(pkgs)"

# Copy app
RUN rm -rf /srv/shiny-server/*
COPY app.R /srv/shiny-server/app.R

RUN echo 'run_as shiny;\nserver {\n  listen 3838;\n  location / {\n    site_dir /srv/shiny-server;\n    log_dir /var/log/shiny-server;\n    directory_index on;\n  }\n}' \
    > /etc/shiny-server/shiny-server.conf

EXPOSE 3838
CMD ["/usr/bin/shiny-server"]
