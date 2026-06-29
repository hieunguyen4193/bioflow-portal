FROM tronghieunguyen/single_cell_pipeline

COPY install_packages.R /tmp/install_packages.R

RUN Rscript /tmp/install_packages.R && rm /tmp/install_packages.R
