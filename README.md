# boost-conan-cmake

**Integration demonstration** showing modern C++17 development with Conan package management, CMake build system, and AWS Lambda deployment packaging.

## 🎯 About This Project

This is a **demonstration project** showcasing the integration of popular C++ libraries and tools:
- **Boost Libraries**: UUID, Regex, Algorithm, JSON, Timer, Filesystem
- **fmt Library**: Modern C++ formatting with colors and performance  
- **xlnt Library**: Excel file creation and manipulation
- **Conan Package Manager**: Dependency management with Conan 1.66
- **CMake Build System**: Modern CMake with security hardening flags
- **AWS Lambda Packaging**: Cross-platform deployment packaging
- **Security Automation**: CVE scanning and code security auditing

## 🚀 What This Demo Shows

- **C++17 Integration**: Practical examples using modern C++ features
- **Library Integration**: Working examples of Boost, fmt, and xlnt libraries
- **Package Management**: Conan-based dependency management
- **Build Automation**: CMake configuration with security hardening
- **Lambda Packaging**: AWS Lambda deployment with dependency bundling
- **Security Scanning**: Automated CVE and security auditing
- **Docker Containerization**: Multi-stage builds for deployment

## 📦 Demo Application

The demo application (`HelloWorld`) showcases practical usage of all integrated libraries:

### Library Demonstrations
- **Boost.UUID**: Unique identifier generation
- **Boost.Regex**: Email pattern matching and extraction
- **Boost.Algorithm**: String processing and manipulation  
- **Boost.JSON**: JSON creation and serialization
- **Boost.Timer**: Performance measurement and timing
- **Boost.Filesystem**: File operations and path handling
- **fmt Library**: Colored console output and formatting
- **xlnt Library**: Excel workbook creation with formulas and formatting

### Dependencies Used
- **Boost 1.84.0**: Core Boost libraries
- **fmt 10.2.1**: Fast and safe formatting library  
- **xlnt 1.5.0**: Excel file processing

## 🛠️ Building the Demo

### Prerequisites
- C++17 compatible compiler (GCC, Clang, or MSVC)
- CMake 3.16 or higher
- Python 3.6+ for Conan
- Conan 1.66.0

### Automatic Build (Recommended)

The CMake build system automatically handles all dependencies:

```bash
# Clone and build - CMake will auto-install dependencies
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release

# Run the demo
./HelloWorld
```

**No manual conan install needed!** CMake automatically:
- Detects your system configuration
- Downloads and builds missing Conan packages
- Configures all dependencies

### Manual Conan Approaches (Optional)

If you prefer manual control over dependencies:

#### Option 1: Conan 1.x
```bash
pip install conan==1.66.0
mkdir build && cd build
conan install .. --build=missing --settings=build_type=Release
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
```

#### Option 2: Conan 2.x
```bash
pip install conan
# Update conanfile.txt generators to: CMakeDeps, CMakeToolchain
conan install . --output-folder=build --build=missing
cmake -B build -DCMAKE_TOOLCHAIN_FILE=build/conan_toolchain.cmake
cmake --build build --config Release
```

## 📦 AWS Lambda Deployment Example

The project includes a specialized packager script demonstrating AWS Lambda deployment:

```bash
# Package with full libc (RECOMMENDED - includes Ubuntu glibc)
./scripts/packager build/HelloWorld

# Package with default libc (testing only - may have compatibility issues)
./scripts/packager --default-libc build/HelloWorld
```

> **Note**: This packager has been **modified from the original AWS SDK packager** to work better with Docker workflows. Instead of creating a zip file, it creates a `built/` directory for easier Docker integration.
>
> **For traditional zip packaging**, add this command after running the packager:
> ```bash
> cd built && zip --symlinks --recurse-paths lambda-package.zip -- *
> ```
>
> **For the original AWS packager**, see: https://github.com/awslabs/aws-lambda-cpp/blob/master/packaging/packager

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

## 🛡️ Security Scanning Demo

The project demonstrates automated security scanning integration:

### Security Tools Showcased
- **CVE Scanning**: Python-based CVE checker with OSV.dev integration
- **Code Auditing**: Bash-based security pattern detection  
- **Container Scanning**: Trivy-based image vulnerability assessment
- **Secrets Detection**: Gitleaks integration for exposed secrets
- **Static Analysis**: Semgrep and cppcheck for code quality

### GitHub Actions Integration
- Automated security scans on PRs and main branch
- Dependabot integration with security validation  
- SARIF report generation for GitHub Security tab
- Security status reporting and artifact management

## 🔧 Build Configuration

### Compiler and Standards
- **C++17 Standard**: Modern C++ with security hardening flags
- **Compiler Support**: GCC, Clang, and MSVC compatibility
- **Security Features**: Stack protection, format security, PIE enabled
- **Static Analysis**: clang-tidy integration for code quality

### Project Structure Example
```
boost-conan-cmake/
├── src/main.cpp          # Demo application showcasing all libraries
├── scripts/              # Utility scripts
│   ├── packager         # Lambda packaging script
│   ├── cve_security_check.py
│   └── security_audit.sh
├── .github/workflows/   # CI/CD demonstrations
├── CMakeLists.txt      # Build configuration with hardening
├── conanfile.txt       # Conan dependencies
└── Dockerfile          # Multi-stage build example
```

## 🎓 Learning Outcomes

This demonstration project shows practical examples of:
- Modern C++17 development practices
- Package manager integration (Conan)
- Build system configuration (CMake with security hardening)
- Library integration (Boost, fmt, xlnt)
- AWS Lambda packaging for C++ applications
- Automated security scanning and CI/CD workflows
- Docker containerization for C++ applications

## 📝 License

Licensed under the Apache License 2.0. This is a demonstration project showcasing integration patterns - see individual library documentation for production usage guidelines.
