cmake_minimum_required(VERSION 3.16)
project(HelloWorld CXX)

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

set(CONAN_SYSTEM_INCLUDES TRUE)

# Try Conan 2.x first (with toolchain)
if(EXISTS "${CMAKE_BINARY_DIR}/conan_toolchain.cmake")
    message(STATUS "Using Conan 2.x toolchain")
    include(${CMAKE_BINARY_DIR}/conan_toolchain.cmake)
    
    # Find packages the Conan 2.x way
    find_package(Boost REQUIRED)
    find_package(fmt REQUIRED)
    find_package(xlnt REQUIRED)
    
    set(CONAN_LIBS Boost::boost fmt::fmt xlnt::xlnt)
    
elseif(EXISTS "${CMAKE_BINARY_DIR}/conanbuildinfo.cmake")
    # Fallback to Conan 1.x approach
    message(STATUS "Using Conan 1.x approach")
    include(${CMAKE_BINARY_DIR}/conanbuildinfo.cmake)
    conan_basic_setup()
    message(STATUS "CONAN_LIBS: ${CONAN_LIBS}")
    set(CONAN_LIBS ${CONAN_LIBS})
    
else()
    # Try the embedded conan.cmake approach
    message(STATUS "Using embedded conan.cmake approach")
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
        set(CONAN_LIBS ${CONAN_LIBS})
    else ()
        message(FATAL_ERROR "The file conanbuildinfo.cmake doesn't exist, check if conan install was executed.")
    endif ()
endif()

add_executable(HelloWorld src/main.cpp)

# Link libraries based on the Conan approach used
if(EXISTS "${CMAKE_BINARY_DIR}/conan_toolchain.cmake")
    # Conan 2.x approach - use modern CMake targets
    target_link_libraries(HelloWorld ${CONAN_LIBS})
else()
    # Conan 1.x approach - use legacy setup
    link_directories(SYSTEM ${CONAN_LIB_DIRS})
    link_libraries(${CONAN_LIBS})
    include_directories(SYSTEM ${CONAN_INCLUDE_DIRS})
endif()

include(CTest)
enable_testing()
