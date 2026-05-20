# Multi-stage Dockerfile for SeqSero2S - NO CONDA VERSION
# Default build: docker build -f Dockerfile.no-conda -t seqsero2s:latest .
# Test build: docker build -f Dockerfile.no-conda --target test -t seqsero2s:test .

# ============================================================================
# Stage 1: Base image with working mlst and Perl 5.34
# ============================================================================
FROM staphb/mlst:latest AS base

LABEL maintainer="justin.payne@fda.hhs.gov"
LABEL description="Simplified Salmonella serotype prediction from genome sequencing data"

ENV DEBIAN_FRONTEND=noninteractive

# ============================================================================
# Stage 2: Builder - Install all dependencies from source/binaries
# ============================================================================
FROM base AS builder

# Version pinning
ARG PYTHON_VERSION=3.10
ARG SAMTOOLS_VERSION=1.19
ARG BEDTOOLS_VERSION=2.31.0
ARG SRA_TOOLS_VERSION=3.0.10
ARG SPADES_VERSION=3.15.5
ARG SALMID_VERSION=0.1.23
ARG BWA_VERSION=0.7.17
ARG STRINGMLST_VERSION=0.6.3
ARG BLAST_VERSION=2.17.0

# Install build dependencies and Python
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    wget \
    ca-certificates \
    zlib1g-dev \
    libbz2-dev \
    liblzma-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libncurses5-dev \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-dev \
    python${PYTHON_VERSION}-distutils \
    python3-pip \
    autoconf \
    git \
    cmake \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set up python alternatives
RUN update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1

WORKDIR /tmp/build

# Install BLAST+ from NCBI pre-compiled binaries
RUN wget --no-check-certificate \
    https://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/LATEST/ncbi-blast-${BLAST_VERSION}+-x64-linux.tar.gz && \
    tar -xzf ncbi-blast-${BLAST_VERSION}+-x64-linux.tar.gz && \
    cp ncbi-blast-${BLAST_VERSION}+/bin/* /usr/local/bin/ && \
    rm -rf ncbi-blast-${BLAST_VERSION}+*

# Install samtools from source
RUN wget --no-check-certificate https://github.com/samtools/samtools/releases/download/${SAMTOOLS_VERSION}/samtools-${SAMTOOLS_VERSION}.tar.bz2 && \
    tar -xjf samtools-${SAMTOOLS_VERSION}.tar.bz2 && \
    cd samtools-${SAMTOOLS_VERSION} && \
    ./configure --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf samtools-${SAMTOOLS_VERSION}*

# Install bedtools from source
RUN wget --no-check-certificate https://github.com/arq5x/bedtools2/releases/download/v${BEDTOOLS_VERSION}/bedtools-${BEDTOOLS_VERSION}.tar.gz && \
    tar -xzf bedtools-${BEDTOOLS_VERSION}.tar.gz && \
    cd bedtools2 && \
    make -j$(nproc) && \
    cp bin/* /usr/local/bin/ && \
    cd .. && \
    rm -rf bedtools*

# Install bwa from source
# Patch for gcc-10+ multiple definition error
RUN wget --no-check-certificate https://github.com/lh3/bwa/archive/v${BWA_VERSION}.tar.gz && \
    tar -xzf v${BWA_VERSION}.tar.gz && \
    cd bwa-${BWA_VERSION} && \
    sed -i 's/const uint8_t rle_auxtab\[8\]/extern const uint8_t rle_auxtab[8]/' rle.h && \
    make -j$(nproc) && \
    cp bwa /usr/local/bin/ && \
    cd .. && \
    rm -rf bwa-* v${BWA_VERSION}.tar.gz

# Install seqtk from source
RUN wget --no-check-certificate https://github.com/lh3/seqtk/archive/refs/heads/master.tar.gz -O seqtk.tar.gz && \
    tar -xzf seqtk.tar.gz && \
    cd seqtk-master && \
    make -j$(nproc) && \
    cp seqtk /usr/local/bin/ && \
    cd .. && \
    rm -rf seqtk-master seqtk.tar.gz

# Install SPAdes from pre-compiled binary
RUN wget --no-check-certificate https://github.com/ablab/spades/releases/download/v${SPADES_VERSION}/SPAdes-${SPADES_VERSION}-Linux.tar.gz && \
    tar -xzf SPAdes-${SPADES_VERSION}-Linux.tar.gz && \
    cp -r SPAdes-${SPADES_VERSION}-Linux/bin/* /usr/local/bin/ && \
    cp -r SPAdes-${SPADES_VERSION}-Linux/share/spades /usr/local/share/ && \
    rm -rf SPAdes-${SPADES_VERSION}-Linux*

# Install SRA Tools from pre-compiled binary
RUN wget --no-check-certificate https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/${SRA_TOOLS_VERSION}/sratoolkit.${SRA_TOOLS_VERSION}-ubuntu64.tar.gz && \
    tar -xzf sratoolkit.${SRA_TOOLS_VERSION}-ubuntu64.tar.gz && \
    cp -r sratoolkit.${SRA_TOOLS_VERSION}-ubuntu64/bin/* /usr/local/bin/ && \
    rm -rf sratoolkit.${SRA_TOOLS_VERSION}-ubuntu64*

# Install Python packages
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel

# Install SalmID from GitHub (not on PyPI)
RUN wget --no-check-certificate https://github.com/hcdenbakker/SalmID/archive/refs/tags/${SALMID_VERSION}.tar.gz -O salmid.tar.gz && \
    tar -xzf salmid.tar.gz && \
    cd SalmID-${SALMID_VERSION} && \
    python3 -m pip install --no-cache-dir . && \
    cd .. && \
    rm -rf SalmID-${SALMID_VERSION} salmid.tar.gz

# Install stringMLST from PyPI
RUN python3 -m pip install --no-cache-dir stringmlst==${STRINGMLST_VERSION}

# Copy and install SeqSero2S from local fork
COPY ./SeqSero2S ./SeqSero2S
RUN python3 -m pip install ./SeqSero2S --no-deps --no-build-isolation --no-cache-dir

# Apply the stringMLST.py patch to fix log path
RUN if [ -f "/usr/local/bin/stringMLST.py" ]; then \
        sed -i 's|            log = dbPrefix+'\''\.log'\''|            # log = dbPrefix+'\''\.log'\''\n            log = os.path.join(os.getcwd(), "kmer.log")|g' /usr/local/bin/stringMLST.py && \
        echo "PATCHED: stringMLST.py log path fixed"; \
    else \
        echo "SKIP: stringMLST.py not found"; \
    fi

# ============================================================================
# Stage 3: Test image - runs validation tests
# ============================================================================
FROM builder AS test

WORKDIR /test

# Run test commands
RUN echo "Running SeqSero2S tests..." && \
    SeqSero2S.py -h && \
    echo "SeqSero2S.py -h: PASSED" && \
    blastn -help && \
    echo "blastn -help: PASSED" && \
    SalmID.py -h && \
    echo "SalmID.py -h: PASSED" && \
    mlst -h && \
    echo "mlst -h: PASSED" && \
    mlst --list | grep -q "senterica_achtman_2" && \
    echo "mlst --list | grep senterica_achtman_2: PASSED" && \
    samtools --version && \
    echo "samtools: PASSED" && \
    bedtools --version && \
    echo "bedtools: PASSED" && \
    bwa 2>&1 | grep -q "index sequences" && \
    echo "bwa: PASSED" && \
    seqtk 2>&1 | grep -q "Usage:" && \
    echo "seqtk: PASSED" && \
    spades.py --version && \
    echo "spades: PASSED" && \
    echo "All tests completed successfully!"

CMD ["echo", "All SeqSero2S tests passed successfully!"]

# ============================================================================
# Stage 4: Production/Distribution image - minimal runtime (DEFAULT)
# ============================================================================
FROM ubuntu:jammy AS dist

# Install ONLY runtime dependencies (no -dev packages, no build tools)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    procps \
    zlib1g \
    libbz2-1.0 \
    liblzma5 \
    libcurl4 \
    libssl3 \
    libncurses5 \
    python3.10 \
    python3.10-minimal \
    libpython3.10-stdlib \
    perl \
    perl-base \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy compiled binaries ONLY (not entire /usr/local)
COPY --from=builder /usr/local/bin/blastn /usr/local/bin/
COPY --from=builder /usr/local/bin/blastp /usr/local/bin/
COPY --from=builder /usr/local/bin/blastx /usr/local/bin/
COPY --from=builder /usr/local/bin/makeblastdb /usr/local/bin/
COPY --from=builder /usr/local/bin/samtools /usr/local/bin/
COPY --from=builder /usr/local/bin/bedtools /usr/local/bin/
COPY --from=builder /usr/local/bin/bwa /usr/local/bin/
COPY --from=builder /usr/local/bin/seqtk /usr/local/bin/
COPY --from=builder /usr/local/bin/spades.py /usr/local/bin/
COPY --from=builder /usr/local/bin/fastq-dump /usr/local/bin/
COPY --from=builder /usr/local/bin/fasterq-dump /usr/local/bin/
COPY --from=builder /usr/local/bin/SalmID.py /usr/local/bin/

# Copy Python scripts/packages (only dist-packages, not whole python install)
COPY --from=builder /usr/local/lib/python3.10/dist-packages /usr/local/lib/python3.10/dist-packages

# Copy Python scripts to bin
COPY --from=builder /usr/local/lib/python3.10/dist-packages/bin/* /usr/local/bin/

# Copy SPAdes shared files (required for spades.py to run)
COPY --from=builder /usr/local/share/spades /usr/local/share/spades

# Copy mlst and its dependencies from base (StaphB image)
COPY --from=base /mlst-2.32.2 /mlst-2.32.2

# Copy perl modules required by mlst
COPY --from=base /usr/share/perl5 /usr/share/perl5
COPY --from=base /usr/lib/x86_64-linux-gnu/perl5 /usr/lib/x86_64-linux-gnu/perl5

# Symlink mlst to standard location
RUN ln -s /mlst-2.32.2/bin/mlst /usr/local/bin/mlst

# Set up python symlinks
RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/bin/python3.10 /usr/bin/python3

# Update PATH
ENV PATH=/usr/local/bin:$PATH \
    PYTHONPATH=/usr/local/lib/python3.10/dist-packages

# Create working directory
WORKDIR /data

# Create non-root user
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
