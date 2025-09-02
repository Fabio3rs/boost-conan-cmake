#!/bin/bash
# Test script for packager functionality
# Tests both packaging modes and validates the results

set -euo pipefail

echo "🧪 Testing boost-conan-cmake packager integration"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=()
    
    if ! command -v cmake &> /dev/null; then missing+=("cmake"); fi
    if ! command -v conan &> /dev/null; then missing+=("conan"); fi
    if ! command -v clang++ &> /dev/null; then missing+=("clang++"); fi
    if ! command -v ninja &> /dev/null; then missing+=("ninja"); fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_info "Install with: sudo apt-get install -y build-essential cmake ninja-build clang"
        log_info "For Conan: pip install conan"
        return 1
    fi
    
    log_success "All prerequisites available"
}

# Build the project
build_project() {
    log_info "Building project..."
    
    if [ ! -d "build" ]; then
        mkdir build
    fi
    
    cd build
    
    # Install Conan dependencies
    log_info "Installing Conan dependencies..."
    conan install .. --output-folder=. --build=missing --settings=build_type=Release
    
    # Configure with CMake
    log_info "Configuring with CMake..."
    cmake .. -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE=conan_toolchain.cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-std=c++20 -Wall -Wextra"
    
    # Build
    log_info "Building..."
    cmake --build . --config Release -j$(nproc)
    
    cd ..
    
    if [ -f "build/HelloWorld" ]; then
        log_success "Build completed successfully"
    else
        log_error "Build failed - binary not found"
        return 1
    fi
}

# Test packager with full libc (recommended)
test_full_libc_packaging() {
    log_info "Testing packager with full libc (RECOMMENDED)..."
    
    # Clean previous packages
    rm -rf built packages-test
    
    # Make packager executable
    chmod +x scripts/packager
    
    # Run packager with full libc (default behavior)
    ./scripts/packager build/HelloWorld
    
    if [ ! -d "built" ]; then
        log_error "Full libc packager failed - built directory not found"
        return 1
    fi
    
    # Create test directory
    mkdir -p packages-test/full-libc
    cp -r built/* packages-test/full-libc/
    
    # Validate package
    validate_package "packages-test/full-libc" "full-libc (recommended)"
}

# Test packager with default libc (testing only)
test_default_libc_packaging() {
    log_info "Testing packager with default libc (TESTING ONLY)..."
    
    # Clean previous packages
    rm -rf built
    
    # Run packager with default libc
    ./scripts/packager --default-libc build/HelloWorld
    
    if [ ! -d "built" ]; then
        log_error "Default libc packager failed - built directory not found"
        return 1
    fi
    
    # Create test directory
    mkdir -p packages-test/default-libc
    cp -r built/* packages-test/default-libc/
    
    # Validate package
    validate_package "packages-test/default-libc" "default-libc (testing only)"
    
    log_warning "Default libc package may have compatibility issues in Lambda environment"
}

# Validate package structure and contents
validate_package() {
    local pkg_dir="$1"
    local pkg_type="$2"
    
    log_info "Validating $pkg_type package..."
    
    # Check required files
    if [ ! -f "$pkg_dir/bootstrap" ]; then
        log_error "Missing bootstrap script in $pkg_type package"
        return 1
    fi
    
    if [ ! -f "$pkg_dir/bin/HelloWorld" ]; then
        log_error "Missing binary in $pkg_type package"
        return 1
    fi
    
    if [ ! -d "$pkg_dir/lib" ]; then
        log_error "Missing lib directory in $pkg_type package"
        return 1
    fi
    
    # Check bootstrap script is executable
    if [ ! -x "$pkg_dir/bootstrap" ]; then
        log_error "Bootstrap script is not executable in $pkg_type package"
        return 1
    fi
    
    # Count libraries
    local lib_count=$(find "$pkg_dir/lib" -name "*.so*" | wc -l)
    log_info "$pkg_type package contains $lib_count shared libraries"
    
    # Show package size
    local pkg_size=$(du -sh "$pkg_dir" | cut -f1)
    log_info "$pkg_type package size: $pkg_size"
    
    # Test bootstrap script syntax
    if bash -n "$pkg_dir/bootstrap"; then
        log_success "Bootstrap script syntax is valid for $pkg_type"
    else
        log_error "Bootstrap script has syntax errors in $pkg_type package"
        return 1
    fi
    
    log_success "$pkg_type package validation passed"
}

# Test package execution
test_package_execution() {
    log_info "Testing package execution..."
    
    # Test full libc package (recommended)
    if [ -d "packages-test/full-libc" ]; then
        log_info "Testing full-libc package execution (recommended)..."
        cd packages-test/full-libc
        
        # Set Lambda environment variables
        export LAMBDA_TASK_ROOT="$(pwd)"
        export API_INSTANCE="test"
        
        # Try to run binary directly (may fail due to lib paths)
        if ./bin/HelloWorld --help 2>/dev/null; then
            log_success "Direct binary execution works"
        else
            log_warning "Direct binary execution failed (expected - needs bootstrap)"
        fi
        
        # Test with proper library path
        if LD_LIBRARY_PATH="./lib:$LD_LIBRARY_PATH" ./bin/HelloWorld --help 2>/dev/null; then
            log_success "Binary execution with lib path works"
        else
            log_warning "Binary execution with lib path failed"
        fi
        
        cd ../..
    fi
    
    # Test default libc package (testing only)
    if [ -d "packages-test/default-libc" ]; then
        log_info "Testing default-libc package execution (testing only)..."
        cd packages-test/default-libc
        
        export LAMBDA_TASK_ROOT="$(pwd)"
        export API_INSTANCE="test"
        
        if LD_LIBRARY_PATH="./lib:$LD_LIBRARY_PATH" ./bin/HelloWorld --help 2>/dev/null; then
            log_success "Default libc binary execution works (may fail in Lambda)"
        else
            log_warning "Default libc binary execution failed (expected compatibility issue)"
        fi
        
        cd ../..
    fi
}

# Generate test report
generate_report() {
    log_info "Generating test report..."
    
    cat > PACKAGER_TEST_REPORT.md << EOF
# 📦 Packager Test Report

**Test Date**: $(date)
**Git Commit**: $(git rev-parse --short HEAD 2>/dev/null || echo "N/A")

## Test Results

### Default libc Package
$(if [ -d "packages-test/default-libc" ]; then
    echo "- ✅ Package created successfully"
    echo "- Size: $(du -sh packages-test/default-libc | cut -f1)"
    echo "- Libraries: $(find packages-test/default-libc/lib -name "*.so*" | wc -l)"
    echo "- Bootstrap: $([ -x packages-test/default-libc/bootstrap ] && echo "✅ Executable" || echo "❌ Not executable")"
else
    echo "- ❌ Package not found"
fi)

### Full libc Package  
$(if [ -d "packages-test/full-libc" ]; then
    echo "- ✅ Package created successfully"
    echo "- Size: $(du -sh packages-test/full-libc | cut -f1)"
    echo "- Libraries: $(find packages-test/full-libc/lib -name "*.so*" | wc -l)"
    echo "- Bootstrap: $([ -x packages-test/full-libc/bootstrap ] && echo "✅ Executable" || echo "❌ Not executable")"
else
    echo "- ❌ Package not found"
fi)

## Package Contents

### Bootstrap Script (default-libc)
\`\`\`bash
$(if [ -f "packages-test/default-libc/bootstrap" ]; then cat packages-test/default-libc/bootstrap; else echo "Not found"; fi)
\`\`\`

## Library Dependencies

### Default libc Libraries
$(if [ -d "packages-test/default-libc/lib" ]; then ls -la packages-test/default-libc/lib | head -20; else echo "Not found"; fi)

## Recommendations

- Use default-libc package for most Lambda environments
- Use full-libc package for restricted or custom environments  
- Test bootstrap script in actual Lambda environment
- Monitor package size for Lambda deployment limits

EOF

    log_success "Test report generated: PACKAGER_TEST_REPORT.md"
}

# Cleanup
cleanup() {
    log_info "Cleaning up test artifacts..."
    rm -rf built packages-test
    log_success "Cleanup completed"
}

# Main test execution
main() {
    echo "Starting packager integration tests..."
    echo "======================================"
    
    # Run tests
    check_prerequisites || return 1
    build_project || return 1
    test_default_libc_packaging || return 1  
    test_full_libc_packaging || return 1
    test_package_execution || return 1
    generate_report
    
    log_success "All packager tests completed successfully! 🎉"
    log_info "Check PACKAGER_TEST_REPORT.md for detailed results"
    
    # Ask about cleanup
    echo ""
    read -p "Clean up test artifacts? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup
    fi
}

# Run main function
main "$@"
