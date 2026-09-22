FROM docker.osgeo.org/geoserver:3.0.0

USER root
RUN apt-get update --allow-insecure-repositories --allow-unauthenticated && \
    apt-get install -y --no-install-recommends --allow-unauthenticated \
    curl \
    jq \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# UID 999 = tomcat user when RUN_UNPRIVILEGED=true
RUN mkdir -p /opt/additional_libs /opt/geoserver_data /var/geoserver/datadir /config && \
    chown -R 999:999 /opt/additional_libs \
                    /opt/geoserver_data \
                    /var/geoserver/datadir \
                    /opt/startup.sh \
                    /usr/local/tomcat/conf \
                    /usr/local/tomcat/webapps \
                    /usr/local/tomcat/logs \
                    /usr/local/tomcat/temp \
                    /usr/local/tomcat/work && \
    chmod -R 775 /var/geoserver/datadir /opt/additional_libs

# WFS outputFormat=gpkg. Build-time only: leaving INSTALL_EXTENSIONS in the image
# would make startup.sh download the plugin again on every container start.
RUN INSTALL_EXTENSIONS=true STABLE_EXTENSIONS=geopkg-output /opt/install-extensions.sh \
    && chown -R 999:999 /opt/additional_libs

# Build context: rer-dsp-core/config
COPY GeoserverDownload/docker/populate_geoserver.sh /opt/populate_geoserver.sh
COPY GeoserverDownload/docker/docker-entrypoint.sh /docker-entrypoint.sh
COPY docker/select-runtime-config.sh /tmp/select-runtime-config.sh
COPY map/ /tmp/map/
RUN chmod +x /opt/populate_geoserver.sh /docker-entrypoint.sh /tmp/select-runtime-config.sh && \
    /tmp/select-runtime-config.sh pick /tmp/map mapLayersConfig.json /config/mapLayersConfig.json && \
    rm -rf /tmp/map /tmp/select-runtime-config.sh && \
    chown 999:999 /opt/populate_geoserver.sh /docker-entrypoint.sh /config/mapLayersConfig.json

ENV GEOSERVER_DATA_DIR=/var/geoserver/datadir

ENTRYPOINT ["/docker-entrypoint.sh"]
