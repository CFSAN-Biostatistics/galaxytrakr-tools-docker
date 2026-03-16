# =============================================================
#   Dockerfile for refchooser (compatible with Galaxy)
# =============================================================

# ---------- Build Stage 1: The "Builder" ----------
# This stage downloads and prepares all our dependencies.
FROM ubuntu:20.04 AS builder

# Set versions for our tools to make updates easy.
ARG MASH_VER="2.3"
ARG PYTHON_VER="3.8"

# Avoid interactive prompts during apt-get install.
ENV DEBIAN_FRONTEND=noninteractive

# Install all the dependencies needed to build our tools.
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    tar \
    gzip \
    python${PYTHON_VER} \
    python${PYTHON_VER}-venv \
    && rm -rf /var/lib/apt/lists/*

# Set a working directory for our downloads.
WORKDIR /build

# --- Install Mash ---
# Download the pre-compiled Linux binary for Mash.
ADD https://github.com/marbl/Mash/releases/download/v${MASH_VER}/mash-Linux64-v${MASH_VER}.tar .
# Unpack the tarball, find the 'mash' executable, and install it to a standard location.
RUN tar -xvf mash-Linux64-v${MASH_VER}.tar && \
    install -m 0755 mash-Linux64-v${MASH_VER}/mash /usr/local/bin/mash

# --- Install refchooser ---
# Create a Python virtual environment in a standard location.
RUN python${PYTHON_VER} -m venv /opt/venv
# Activate the venv and install refchooser and its dependencies using pip.
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir refchooser


# ---------- Build Stage 2: The "Runtime" Stage ----------
# This is our final, lean image that will be used by Galaxy.
FROM ubuntu:20.04 AS runtime

# Avoid interactive prompts.
ENV DEBIAN_FRONTEND=noninteractive

# Install only the essential runtime libraries needed by Mash and Python.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    python3.8-venv \
    && rm -rf /var/lib/apt/lists/*

# --- Copy Binaries and Environment from Builder Stage ---

# Copy the compiled 'mash' binary from the builder stage.
COPY --from=builder /usr/local/bin/mash /usr/local/bin/mash

# Copy the entire Python virtual environment containing 'refchooser'.
COPY --from=builder /opt/venv /opt/venv

# --- Final Configuration ---

# Set the PATH environment variable so the system can find 'mash' and 'refchooser'.
ENV PATH="/opt/venv/bin:$PATH"

# As a best practice for Galaxy, ensure all users can read and execute the tools.
RUN chmod -R a+rX /opt/venv && \
    chmod a+rx /usr/local/bin/mash

# IMPORTANT: No ENTRYPOINT. Set a neutral CMD for Galaxy compatibility.
CMD ["/bin/bash"]
