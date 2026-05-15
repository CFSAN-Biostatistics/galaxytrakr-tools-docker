# Multi-stage Dockerfile for SeqSero2S
# Default build: docker build -t seqsero2s:latest .
# Test build: docker build --target test -t seqsero2s:test .

# ============================================================================
# Stage 1: Base image with mambaforge for faster dependency resolution
# ============================================================================
FROM condaforge/mambaforge:latest AS base

LABEL maintainer="SeqSero2S Maintainers"
LABEL description="Simplified Salmonella serotype prediction from genome sequencing data"

# Set environment variables to reduce conda output and ensure non-interactive
# Disable SSL verification for VPN environments
ENV CONDA_ALWAYS_YES=true \
    CONDA_AUTO_UPDATE_CONDA=false \
    DEBIAN_FRONTEND=noninteractive

# Configure conda to skip SSL verification
RUN conda config --set ssl_verify false

# ============================================================================
# Stage 2: Builder - Install all dependencies and SeqSero2S
# ============================================================================
FROM base AS builder

# Update base packages and install build essentials
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget \
        ca-certificates \
        bash \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy the patch script
COPY patch_stringmlst.sh /tmp/patch_stringmlst.sh
RUN chmod +x /tmp/patch_stringmlst.sh

# Create conda environment with all dependencies
# Using mamba for faster dependency resolution
RUN mamba create -n seqsero2s -c conda-forge -c bioconda \
    python>=3 \
    pip \
    setuptools \
    blast>=2.2 \
    zstd \
    samtools \
    bedtools>=2.17 \
    sra-tools>=2.8 \
    spades>=3.9 \
    salmid \
    bwa>=0.7 \
    seqtk>=1.3 \
    stringmlst>=0.6 \
    mlst>=2.32.2 \
    perl-list-moreutils \
    && mamba clean -afy

# Install SeqSero2S from local fork
WORKDIR /tmp/build

# Copy local SeqSero2S directory
COPY SeqSero2S /tmp/build/SeqSero2S

# Install SeqSero2S
RUN cd SeqSero2S && \
    /opt/conda/envs/seqsero2s/bin/python -m pip install . -vv --no-deps --no-build-isolation --no-cache-dir

# Apply the stringMLST.py patch (from the conda recipe)
# The patch replaces dbPrefix reference with cwd to avoid path issues
RUN PREFIX=/opt/conda/envs/seqsero2s /tmp/patch_stringmlst.sh

# ============================================================================
# Stage 3: Test image - runs validation tests
# ============================================================================
FROM builder AS test

# Create test directory
WORKDIR /test

# Run test commands from the conda recipe
RUN echo "Running SeqSero2S tests..." && \
    /opt/conda/envs/seqsero2s/bin/SeqSero2S.py -h && \
    echo "SeqSero2S.py -h: PASSED" && \
    /opt/conda/envs/seqsero2s/bin/blastn -help && \
    echo "blastn -help: PASSED" && \
    /opt/conda/envs/seqsero2s/bin/SalmID.py -h && \
    echo "SalmID.py -h: PASSED" && \
    /opt/conda/envs/seqsero2s/bin/mlst -h && \
    echo "mlst -h: PASSED" && \
    echo "All tests completed successfully!"

# Default command shows test results
CMD ["echo", "All SeqSero2S tests passed successfully!"]

# ============================================================================
# Stage 4: Production/Distribution image - minimal runtime (DEFAULT)
# ============================================================================
FROM condaforge/mambaforge:latest AS dist

# Copy conda environment from builder
COPY --from=builder /opt/conda/envs/seqsero2s /opt/conda/envs/seqsero2s

# Update PATH to use the conda environment
ENV PATH=/opt/conda/envs/seqsero2s/bin:$PATH \
    CONDA_DEFAULT_ENV=seqsero2s \
    CONDA_PREFIX=/opt/conda/envs/seqsero2s

# Install minimal runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        procps \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create working directory
WORKDIR /data

# Create non-root user for running the application
RUN useradd -m -u 1000 -s /bin/bash seqsero2s && \
    chown -R seqsero2s:seqsero2s /data

USER seqsero2s

# Add metadata labels
LABEL org.opencontainers.image.version="1.1.4" \
      org.opencontainers.image.authors="LSTUGA" \
      org.opencontainers.image.url="https://github.com/LSTUGA/SeqSero2S" \
      org.opencontainers.image.documentation="https://github.com/LSTUGA/SeqSero2S" \
      org.opencontainers.image.source="https://github.com/LSTUGA/SeqSero2S" \
      org.opencontainers.image.licenses="GPL-2.0-or-later" \
      org.opencontainers.image.title="SeqSero2S" \
      org.opencontainers.image.description="Simplified Salmonella serotype prediction from genome sequencing data"

# No entrypoint or command for dist target
