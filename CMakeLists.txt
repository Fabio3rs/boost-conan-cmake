cmake_minimum_required(VERSION 3.16)
project(HelloWorld CXX)

# Conan Integration:
# This project uses embedded conan.cmake for automatic dependency management by default.
# Simply run cmake and it will auto-detect settings and build missing dependencies.
# 
# Manual Conan approaches are supported as alternatives:
# - Conan 1.x: Run "conan install .. --build=missing" then cmake
# - Conan 2.x: Change generators to CMakeDeps/CMakeToolchain, run conan install, then cmake with toolchain

set(CONAN_SYSTEM_INCLUDES TRUE)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_DEFAULT 17)
set(CXX17 ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_EXTENSIONS ON)
set(CMAKE_C_EXTENSIONS ON)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fdata-sections -ffunction-sections")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fdata-sections -ffunction-sections")

# Security hardening flags (recommended by security scanner)
option(ENABLE_HARDENING "Enable security hardening flags" ON)
if(ENABLE_HARDENING)
    # Stack protection
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fstack-protector-strong")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fstack-protector-strong")
    
    # Buffer overflow detection  
    add_compile_definitions(_FORTIFY_SOURCE=2)
    
    # Format string protection
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wformat -Wformat-security")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wformat -Wformat-security")
    
    # Position independent executable (PIE)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIE")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIE")
    
    # Linker hardening flags
    add_link_options("-Wl,-z,relro,-z,now")  # RELRO + immediate binding
    add_link_options("-pie")                 # PIE linking
endif()

add_link_options("-Wl,--gc-sections")

# Primary approach: Embedded conan.cmake (automatic dependency management)
if(EXISTS "${CMAKE_BINARY_DIR}/conanbuildinfo.cmake")
    # Manual Conan 1.x approach (if user ran conan install manually)
    message(STATUS "Using manual Conan 1.x approach")
    include(${CMAKE_BINARY_DIR}/conanbuildinfo.cmake)
    conan_basic_setup()
    message(STATUS "CONAN_LIBS: ${CONAN_LIBS}")
    set(DEFAULT_LIBS ${CONAN_LIBS})
    
elseif(EXISTS "${CMAKE_BINARY_DIR}/conan_toolchain.cmake")
    # Manual Conan 2.x approach (if user configured for Conan 2.x)
    message(STATUS "Using manual Conan 2.x toolchain")
    include(${CMAKE_BINARY_DIR}/conan_toolchain.cmake)
    
    # Find packages - use available targets
    find_package(Boost REQUIRED)
    find_package(fmt REQUIRED)
    
    # For xlnt, try to find it but make it optional in case it doesn't provide proper CMake config
    find_package(xlnt QUIET)
    
    if(TARGET xlnt::xlnt)
        set(DEFAULT_LIBS Boost::boost fmt::fmt xlnt::xlnt)
        message(STATUS "Using xlnt::xlnt target")
    else()
        # Fallback to trying other possible target names for xlnt
        if(TARGET xlnt)
            set(DEFAULT_LIBS Boost::boost fmt::fmt xlnt)
            message(STATUS "Using xlnt target")
        else()
            # If no CMake targets, xlnt should still be available through link directories
            set(DEFAULT_LIBS Boost::boost fmt::fmt)
            message(STATUS "xlnt target not found, will rely on link directories")
        endif()
    endif()
    
else()
    # Default: Embedded conan.cmake approach (automatic)
    message(STATUS "Using embedded conan.cmake approach (automatic dependency management)")
    include(${PROJECT_SOURCE_DIR}/cmake/conan.cmake)

    conan_cmake_autodetect(CONAN_SETTINGS)

    conan_cmake_run(CONANFILE conanfile.txt
            BASIC_SETUP CMAKE_TARGETS
            BUILD missing
            SETTINGS ${CONAN_SETTINGS}
            ENV "CXXFLAGS=-fdata-sections -ffunction-sections"
            ENV "CFLAGS=-fdata-sections -ffunction-sections")

    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS conanfile.txt)

    if (EXISTS "${CMAKE_BINARY_DIR}/conanbuildinfo.cmake")
        include(${CMAKE_BINARY_DIR}/conanbuildinfo.cmake)
        conan_basic_setup()
        message(STATUS "CONAN_LIBS: ${CONAN_LIBS}")
        set(DEFAULT_LIBS ${CONAN_LIBS})
    else ()
        message(FATAL_ERROR "The file conanbuildinfo.cmake doesn't exist, check if conan install was executed.")
    endif ()
endif()

# Setup linking based on the approach used
if(EXISTS "${CMAKE_BINARY_DIR}/conan_toolchain.cmake")
    # For manual Conan 2.x approach, use target-based linking only
    add_executable(HelloWorld src/main.cpp)
    target_link_libraries(HelloWorld ${DEFAULT_LIBS})
else()
    # For embedded conan.cmake and manual Conan 1.x, use original approach
    link_directories(SYSTEM ${CONAN_LIB_DIRS})
    link_libraries(${DEFAULT_LIBS})
    include_directories(SYSTEM ${CONAN_INCLUDE_DIRS})
    
    add_executable(HelloWorld src/main.cpp)
endif()

include(CTest)
enable_testing()
