# Multi-stage Dockerfile for boost-conan-cmake
# Following C++ Core Guidelines and NASA Power of Ten principles

# Build stage - Ubuntu 24.04 for comprehensive development tools
FROM ubuntu:24.04 AS builder

LABEL maintainer="boost-conan-cmake-team"
LABEL description="Build environment for boost-conan-cmake C++20/23 project"

# Install system dependencies with security updates
RUN apt-get update && apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    # Core build tools
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    git \
    curl \
    wget \
    ca-certificates \
    # Clang/LLVM toolchain for C++20/23
    clang-18 \
    clang-tidy-18 \
    clang-format-18 \
    lldb-18 \
    libc++-18-dev \
    libc++abi-18-dev \
    # Python for Conan and scripts
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    # Security and analysis tools
    valgrind \
    cppcheck \
    # Development libraries
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    # Clean up
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Set up C++20/23 environment with Clang
ENV CC=clang-18
ENV CXX=clang++-18
ENV CXXFLAGS="-std=c++20 -Wall -Wextra -Wpedantic -march=native -O2 -DNDEBUG"
ENV CFLAGS="-Wall -Wextra -Wpedantic -march=native -O2 -DNDEBUG"

# Install Conan 1.x without upgrading pip (pip 24.0 is sufficient)
RUN python3 -m pip install --break-system-packages --no-cache-dir \
    conan==1.66.0 \
    requests \
    jq

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash --uid 1001 builder
USER builder
WORKDIR /home/builder

# Configure Conan 1.x
RUN conan profile new default --detect --force

# Copy project files
COPY --chown=builder:builder . /home/builder/project
WORKDIR /home/builder/project

# Install dependencies and build using Conan 1.x approach
RUN mkdir -p build && cd build && \
    conan install .. --build=missing --settings=build_type=Release && \
    cmake .. -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-march=native -fdata-sections -ffunction-sections" \
        -DCMAKE_C_FLAGS="-march=native -fdata-sections -ffunction-sections" \
        -DCMAKE_EXE_LINKER_FLAGS="-Wl,--gc-sections" && \
    cmake --build . --config Release -j$(nproc)

# Package dependencies using packager script (includes full libc for compatibility)
RUN chmod +x scripts/packager && \
    ./scripts/packager build/bin/HelloWorld && \
    ls -la built/

# Runtime stage - Alpine for minimal attack surface
FROM alpine:3.22 AS runtime

LABEL maintainer="boost-conan-cmake-team"
LABEL description="Runtime environment for boost-conan-cmake application"

# Install minimal runtime dependencies
RUN apk update && apk upgrade && \
    apk add --no-cache \
    libstdc++ \
    libgcc \
    ca-certificates \
    bash \
    && rm -rf /var/cache/apk/*

# Create non-root user
RUN adduser -D -s /bin/bash -u 1002 appuser

# Create Lambda task root directory structure
ENV LAMBDA_TASK_ROOT=/var/task
RUN mkdir -p $LAMBDA_TASK_ROOT && \
    chown appuser:appuser $LAMBDA_TASK_ROOT

# Copy packaged application with all dependencies
COPY --from=builder --chown=appuser:appuser /home/builder/project/built/ $LAMBDA_TASK_ROOT/

# Ensure bootstrap script is executable
RUN chmod +x $LAMBDA_TASK_ROOT/bootstrap

# Security: switch to non-root user
USER appuser
WORKDIR $LAMBDA_TASK_ROOT

# Health check using the packaged application
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD $LAMBDA_TASK_ROOT/bin/HelloWorld --version || exit 1

# Use bootstrap script as the entrypoint (Lambda-compatible)
ENTRYPOINT ["./bootstrap"]
CMD []
