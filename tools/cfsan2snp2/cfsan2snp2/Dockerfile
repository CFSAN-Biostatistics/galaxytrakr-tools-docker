# =========================
#   CSP2 for Galaxy/AWS Batch (offline Nextflow)
# =========================

# ---------- Build stage ----------
FROM ubuntu:focal AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG CSP2_VER="0.9.0"
ARG BEDTOOLS_VER="2.31.1"
ARG MUMMER_VER="4.0.0"
ARG SKESA_VER="2.4.0"
ARG MASH_VER="2.3"
ARG BBMAP_VER="38.90"
ARG PYTHON_VER="3.8"
ARG SOURCEFORGE_MIRROR="psychz"
ARG IQTREE_VER="2.0.6"

# Use a stable working directory
WORKDIR /workspace

# Base build deps (include Java to verify/prewarm Nextflow here)
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata gpg-agent software-properties-common build-essential \
    zlib1g-dev libghc-bzlib-dev liblzma-dev wget ca-certificates \
    cmake curl git xz-utils openjdk-17-jre-headless \
 && rm -rf /var/lib/apt/lists/*

# Python venv for runtime tools
RUN add-apt-repository 'ppa:deadsnakes/ppa' && apt-get update && \
    apt-get install -y --no-install-recommends \
      python${PYTHON_VER} python${PYTHON_VER}-dev python${PYTHON_VER}-venv \
 && python${PYTHON_VER} -m venv --copies /opt/venv \
 && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/venv/bin:${PATH}"

# Core Python packages
RUN pip install --no-cache-dir -U \
    pandas~=1.2.0 pybedtools refchooser scikit-learn

# ---- Fetch sources/artifacts ----
    
# bedtools
ADD https://github.com/arq5x/bedtools2/archive/refs/tags/v${BEDTOOLS_VER}.tar.gz .
# mummer
ADD https://github.com/mummer4/mummer/releases/download/v${MUMMER_VER}rc1/mummer-${MUMMER_VER}rc1.tar.gz .
# skesa prebuilt bins
ADD https://github.com/ncbi/SKESA/releases/download/${SKESA_VER}/skesa.centos.7.7 .
ADD https://github.com/ncbi/SKESA/releases/download/${SKESA_VER}/gfa_connector.centos7.7 .
ADD https://github.com/ncbi/SKESA/releases/download/${SKESA_VER}/kmercounter.centos7.7 .
# mash
ADD https://github.com/marbl/Mash/releases/download/v${MASH_VER}/mash-Linux64-v${MASH_VER}.tar .
# iqtree2
ADD https://github.com/Cibiv/IQ-TREE/releases/download/v${IQTREE_VER}/iqtree-${IQTREE_VER}-Linux.tar.gz .

# ---- Build/install tools into /usr/local ----
# bedtools
RUN tar -xzf v${BEDTOOLS_VER}.tar.gz && rm v${BEDTOOLS_VER}.tar.gz && \
    cd bedtools2-${BEDTOOLS_VER} && make -j && make install

# Install MUMmer and copy Perl modules where dnadiff expects them
RUN tar -xvf mummer-${MUMMER_VER}rc1.tar.gz && rm mummer-${MUMMER_VER}rc1.tar.gz && \
    cd mummer-${MUMMER_VER}rc1 && \
    ./configure --prefix=/usr/local && make -j && make install && ldconfig && \
    mkdir -p /usr/local/lib/mummer && cp -a scripts/*.pm /usr/local/lib/mummer/

# skesa tools (rename and install)
RUN install -m 0755 skesa.centos.7.7        /usr/local/bin/skesa && \
    install -m 0755 gfa_connector.centos7.7 /usr/local/bin/gfa_connector && \
    install -m 0755 kmercounter.centos7.7   /usr/local/bin/kmercounter

# mash
RUN tar -xvf mash-Linux64-v${MASH_VER}.tar && \
    install -m 0755 mash-Linux64-v${MASH_VER}/mash /usr/local/bin/mash

# bbmap (grab all scripts/binaries)
RUN wget -O BBMap_${BBMAP_VER}.tar.gz \
      "https://sourceforge.net/projects/bbmap/files/BBMap_${BBMAP_VER}.tar.gz/download?use_mirror=${SOURCEFORGE_MIRROR}" && \
    tar -xvf BBMap_${BBMAP_VER}.tar.gz && \
    cp -a bbmap/* /usr/local/bin/ && \
    rm -rf bbmap BBMap_${BBMAP_VER}.tar.gz

# iqtree2
RUN tar -xzf iqtree-${IQTREE_VER}-Linux.tar.gz && \
    install -m 0755 iqtree-${IQTREE_VER}-Linux/bin/iqtree2 /usr/local/bin/iqtree && \
    rm -rf iqtree-${IQTREE_VER}-Linux iqtree-${IQTREE_VER}-Linux.tar.gz

# choose a version
ARG NXF_VER="25.04.7"

# install that exact launcher & prewarm framework into /opt/nextflow
RUN curl -fsSL -o /usr/local/bin/nextflow \
      "https://github.com/nextflow-io/nextflow/releases/download/v${NXF_VER}/nextflow" \
 && chmod 0755 /usr/local/bin/nextflow \
 && mkdir -p /opt/nextflow \
 && chmod -R a+rwX /opt/nextflow \
 && NXF_HOME=/opt/nextflow NXF_OFFLINE=false NXF_VER=${NXF_VER} /usr/local/bin/nextflow -version \
 && ls -l /usr/local/bin/nextflow

# ---------- Runtime stage ----------
FROM ubuntu:focal AS runtime

ARG DEBIAN_FRONTEND=noninteractive
ARG CSP2_VER="0.9.0"

# Python venv for runtime tools
# Lean runtime libs + Python3.8 + Perl (no PPAs)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates openjdk-17-jre-headless bash tzdata perl perl-modules-5.30 \
    libgomp1 liblzma5 zlib1g libbz2-1.0 coreutils make curl gawk \
    python3.8 python3.8-venv python3.8-distutils \
 && rm -rf /var/lib/apt/lists/*

# Bring over tools and Python venv
COPY --from=build /usr/local/bin/ /usr/local/bin/
COPY --from=build /usr/local/libexec/mummer /usr/local/libexec/mummer
COPY --from=build /usr/local/share/ /usr/local/share/
COPY --from=build /opt/venv /opt/venv

# Bring over Nextflow launcher and baked framework cache
COPY --from=build /usr/local/bin/nextflow /usr/local/bin/nextflow
COPY --from=build /opt/nextflow /opt/nextflow

# Ensure any UID (Galaxy user) can execute nextflow and write minimal state into the cache
RUN chmod 0755 /usr/local/bin/nextflow \
 && chmod -R a+rwX /opt/nextflow

# Bring the modules into the runtime image (if not already)
COPY --from=build /usr/local/lib/mummer /usr/local/lib/mummer

# Bring MUMmer shared libs into the runtime image
COPY --from=build /usr/local/lib /usr/local/lib

# Make sure dynamic linker can find them
RUN ldconfig || true

# Belt-and-suspenders for minimal images
ENV LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH}"

# Permissions: allow any UID to read/execute the libs
RUN chmod -R a+rX /usr/local/lib

# Make modules readable by any UID; create compatibility symlink if needed
RUN chmod -R a+rX /usr/local/lib/mummer /usr/local/libexec/mummer && \
    test -d /usr/local/lib/mummer || ln -s /usr/local/libexec/mummer /usr/local/lib/mummer

# Ensure the common mummer executables are executable by all
RUN chmod 0755 /usr/local/bin/dnadiff /usr/local/bin/nucmer /usr/local/bin/promer /usr/local/bin/show-snps || true

# Help Perl find modules regardless of layout
ENV PERL5LIB="/usr/local/lib/mummer:/usr/local/libexec/mummer:/usr/local/share/mummer:${PERL5LIB}"

# Runtime environment
ENV PATH="/opt/venv/bin:/usr/local/bin:${PATH}" \
    LC_ALL=C \
    NXF_HOME=/opt/nextflow \
    NXF_OFFLINE=true \
    CSP2_VER=${CSP2_VER}

# Install the CSP2 pipeline under /opt/csp2 (avoid /app which Galaxy mounts)
WORKDIR /opt/csp2

# Copy your pipeline (these paths must exist in the build context)
COPY bin              ./bin
COPY conf             ./conf
COPY subworkflows     ./subworkflows
COPY CSP2.nf          ./CSP2.nf
COPY nextflow.config  ./nextflow.config

# permissions for arbitrary UID
RUN chmod -R a+rX /opt/csp2 && chmod -R a+rX /opt/nextflow

# IMPORTANT: No ENTRYPOINT for Galaxy/AWS Batch. Neutral CMD.
CMD ["/bin/bash"]
