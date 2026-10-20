FROM apache/airflow:2.10.5-python3.11
USER root
RUN apt-get update && apt-get install -y --no-install-recommends unzip curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# Hop 2.19 needs Java 21 (class file v65); Debian bookworm only ships 17, so use Temurin 21 JRE with checksum from the Adoptium API.
COPY install_java.py /tmp/install_java.py
RUN set -eux; A=$(dpkg --print-architecture); case $A in amd64) T=x64;; arm64) T=aarch64;; esac; \
    python /tmp/install_java.py "$T"
RUN mkdir -p /opt/java && tar -xzf /tmp/jre.tgz -C /opt/java --strip-components=1 && rm /tmp/jre.tgz
ENV JAVA_HOME=/opt/java PATH="/opt/java/bin:${PATH}"
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
COPY --chown=airflow:root hop/ /opt/airflow/hop/
