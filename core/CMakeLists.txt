cmake_minimum_required(VERSION 3.16)
project(gvpb LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(GVPB_SOURCES
    src/gvpb.cpp
    src/schema.cpp
    src/kcp.cpp
    src/fec.cpp
)

# 静态库：三端单测与可执行文件链接
add_library(gvpb STATIC ${GVPB_SOURCES})
target_include_directories(gvpb PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)

# 共享库：给 Windows P/Invoke（gvpb.dll）与 Android JNI（libgvpb.so）共用同一实现
add_library(gvpb_shared SHARED ${GVPB_SOURCES})
target_include_directories(gvpb_shared PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
set_target_properties(gvpb_shared PROPERTIES OUTPUT_NAME gvpb)

add_executable(gvpb_tests tests/test_core.cpp)
target_link_libraries(gvpb_tests PRIVATE gvpb)

enable_testing()
add_test(NAME gvpb_core COMMAND gvpb_tests)
