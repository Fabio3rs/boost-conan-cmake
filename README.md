# boost-conan-cmake

Modern C++20/23 project template with Conan package management, CMake build system, and Lambda-ready deployment packaging.

## 🚀 Features

- **C++20/23 Support**: Modern C++ standards with Clang toolchain
- **Dependency Management**: Conan 2.x for robust package management
- **Build System**: CMake with Ninja generator for fast builds
- **Lambda Deployment**: AWS Lambda-compatible packaging with dependency bundling
- **Security First**: Comprehensive CVE scanning and security auditing
- **Docker Support**: Multi-stage builds with Alpine runtime
- **CI/CD Ready**: GitHub Actions workflows with security validation

## 📦 Dependencies

- **Boost 1.84.0**: Modern Boost libraries
- **fmt 10.2.1**: Fast and safe formatting library  
- **xlnt 1.5.0**: Excel file processing

## 🛠️ Quick Start

### Using Make (Recommended)

```bash
# Build the project
make build

# Package for Lambda deployment (includes full glibc)
make package

# Package for testing only (may have compatibility issues)
make package-default

# Run security analysis
make security

# Docker packaging
make docker-package

# Show all available targets
make help
```

### Manual Build

```bash
# Install dependencies
mkdir build && cd build
conan install .. --output-folder=. --build=missing --settings=build_type=Release

# Configure and build
cmake .. -G Ninja -DCMAKE_TOOLCHAIN_FILE=conan_toolchain.cmake
cmake --build . --config Release
```

## 📦 Lambda Packaging

This project includes a specialized `packager` script for AWS Lambda deployment with **full glibc compatibility**:

```bash
# Package with full libc (RECOMMENDED - includes Ubuntu glibc)
./scripts/packager build/HelloWorld

# Package with default libc (testing only - may have compatibility issues)
./scripts/packager --default-libc build/HelloWorld
```

### Why Full libc?

The **full libc package is recommended** because:
- **Compatibility**: Ensures Ubuntu glibc works in Lambda runtime
- **Reliability**: Prevents musl vs glibc compatibility issues  
- **Production Ready**: Tested approach for cross-platform deployment

The packager creates a `built/` directory with:
- `bin/HelloWorld` - Your application binary
- `lib/` - All required shared libraries **including glibc**
- `bootstrap` - Lambda-compatible entry point script

### Bootstrap Script (Full libc)

The generated bootstrap script handles dynamic loading with included glibc:

```bash
#!/bin/sh
set -euo pipefail
exec $LAMBDA_TASK_ROOT/lib/ld-linux-x86-64.so.2 --library-path $LAMBDA_TASK_ROOT/lib $LAMBDA_TASK_ROOT/bin/HelloWorld $API_INSTANCE
```

## 🐳 Docker Usage

### Docker Usage (Recommended)

```bash
# Build and package everything with Docker
docker build -t boost-conan-cmake:latest .

# Run with Lambda-compatible environment
docker run --rm -it \
  -e LAMBDA_TASK_ROOT=/var/task \
  -e API_INSTANCE=test \
  boost-conan-cmake:latest

# Extract Lambda package from Docker
make docker-extract
```

### Docker Compose

```bash
# Start main application
docker-compose up app

# Development environment
docker-compose up dev

# Run security scans
docker-compose --profile security up security-scanner
```

## 🛡️ Security

### Automated Security Scanning

- **CVE Scanning**: Python-based CVE checker with OSV.dev integration
- **Code Auditing**: Bash-based security pattern detection  
- **Dependency Validation**: Conan package vulnerability checking
- **Container Scanning**: Trivy-based image vulnerability assessment

```bash
# Run all security checks
make security

# Docker security scanning
make docker-security
```

### CI/CD Security Pipeline

- Automated dependency updates via Dependabot
- Security-focused PR validation
- CVE monitoring with failure thresholds
- SARIF report generation for GitHub Security tab

## 🔧 Development

### Code Quality

- **C++20/23 Standards**: Following C++ Core Guidelines
- **NASA Power of Ten**: Safety-critical coding practices
- **Static Analysis**: clang-tidy and cppcheck integration
- **Formatting**: clang-format with consistent style

### Environment Setup

```bash
# Install system dependencies
make install-deps

# Format code
make format

# Run static analysis
make analyze
```

## 📊 CI/CD Workflows

### Build Pipeline
- Multi-platform CMake builds
- Conan dependency caching
- Test execution with CTest

### Security Pipeline  
- Weekly vulnerability scans
- Dependency update validation
- Container image security assessment
- Automated security reporting

### Deployment Pipeline
- Lambda package generation
- Docker image building
- Artifact management

## 🎯 Project Structure

```
boost-conan-cmake/
├── src/                    # Source code
├── scripts/               # Utility scripts
│   ├── packager          # Lambda packaging script
│   ├── cve_security_check.py
│   └── security_audit.sh
├── .github/              # GitHub Actions workflows
│   └── workflows/
├── docker-compose.yml    # Multi-service development
├── Dockerfile           # Multi-stage production build
├── CMakeLists.txt      # Build configuration
├── conanfile.txt       # Dependencies
└── Makefile            # Build automation
```

## 📝 License

Licensed under the Apache License 2.0. See the packager script for AWS Lambda C++ runtime licensing terms.
