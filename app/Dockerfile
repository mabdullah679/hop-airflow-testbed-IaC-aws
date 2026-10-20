FROM apache/airflow:2.10.5-python3.11
USER root
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-17-jre-headless unzip curl \
    && rm -rf /var/lib/apt/lists/*
ARG HOP_VERSION=2.19.0
# downloads.apache.org is fast but only holds the current release; archive.apache.org is the permanent fallback.
RUN set -eux; Z=apache-hop-client-${HOP_VERSION}.zip; \
    for base in https://downloads.apache.org/hop https://archive.apache.org/dist/hop; do \
      curl -fsSL -o /tmp/hop.zip $base/${HOP_VERSION}/$Z && break; done; \
    curl -fsSL -o /tmp/hop.sha512 https://archive.apache.org/dist/hop/${HOP_VERSION}/$Z.sha512; \
    echo "$(cut -d' ' -f1 /tmp/hop.sha512)  /tmp/hop.zip" | sha512sum -c -; \
    unzip -q /tmp/hop.zip -d /opt; rm /tmp/hop.zip /tmp/hop.sha512; \
    chmod +x /opt/hop/*.sh; chown -R airflow /opt/hop
ENV HOP_HOME=/opt/hop PATH="/opt/hop:${PATH}" HOP_OPTIONS="-Xmx512m"
RUN mkdir -p /opt/airflow/work && chown airflow /opt/airflow/work
USER airflow
RUN pip install --no-cache-dir boto3
COPY hop/ /opt/airflow/hop/
