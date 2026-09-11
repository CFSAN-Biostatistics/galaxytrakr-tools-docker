# =============================================================
#   Dockerfile for mitokmer2 (compatible with Galaxy/AWS Batch)
# =============================================================

# ---------- Build Stage ----------
FROM ubuntu:focal AS build

ARG DEBIAN_FRONTEND=noninteractive
ARG PYTHON_VER="3.8"

WORKDIR /workspace

# Build dependencies: compiler, zlib dev headers, git, Python
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    g++ \
    git \
    wget \
    zlib1g-dev \
    ca-certificates \
    python${PYTHON_VER} \
    python${PYTHON_VER}-dev \
    python${PYTHON_VER}-venv \
    && rm -rf /var/lib/apt/lists/*

# Create Python virtual environment using --copies so symlinks
# do not break when the venv is copied to the runtime stage
RUN python${PYTHON_VER} -m venv --copies /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Install Python dependencies (add any additional packages here)
RUN pip install --no-cache-dir -U pip && \
    pip install --no-cache-dir pandas

# Clone mitokmer2 source code from GitHub
RUN git clone https://github.com/mmammel8/mitokmer2.git /opt/mitokmer2

# Compile the two C++ programs
# kmer_build_mt: builds the k-mer probe database
# kmer_read_mt:  screens reads against the probe database
WORKDIR /opt/mitokmer2
RUN g++ -O3 kmer_build_mt.cpp -o kmerbuild -lz && \
    g++ -O3 kmer_read_mt.cpp  -o kmerread  -lz && \
    chmod +x kmerbuild kmerread

# Install any Python requirements declared in the repo
RUN if [ -f requirements.txt ]; then \
        pip install --no-cache-dir -r requirements.txt; \
    fi


# ---------- Runtime Stage ----------
FROM ubuntu:focal AS runtime

ARG DEBIAN_FRONTEND=noninteractive

# Lean runtime: zlib shared library + Python runtime only
RUN apt-get update && apt-get install -y --no-install-recommends \
    zlib1g \
    libbz2-1.0 \
    ca-certificates \
    python3.8 \
    python3.8-venv \
    python3.8-distutils \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled binaries from build stage
COPY --from=build /opt/mitokmer2/kmerbuild /usr/local/bin/kmerbuild
COPY --from=build /opt/mitokmer2/kmerread  /usr/local/bin/kmerread

# Copy Python scripts from build stage
COPY --from=build /opt/mitokmer2 /opt/mitokmer2

# Copy Python virtual environment from build stage
# --copies in the build stage ensures no broken symlinks here
COPY --from=build /opt/venv /opt/venv

# Refresh the dynamic linker cache so zlib and other shared
# libraries copied from the build stage are found at runtime
RUN ldconfig || true

# Ensure all users (including arbitrary Galaxy UIDs) can
# read and execute binaries, scripts, and the venv
RUN chmod a+rx  /usr/local/bin/kmerbuild \
                /usr/local/bin/kmerread && \
    chmod -R a+rX /opt/mitokmer2 && \
    chmod -R a+rX /opt/venv

# Runtime environment
ENV PATH="/opt/venv/bin:/opt/mitokmer2:/usr/local/bin:${PATH}" \
    LC_ALL=C

# IMPORTANT: No ENTRYPOINT for Galaxy/AWS Batch. Neutral CMD.
CMD ["/bin/bash"]
