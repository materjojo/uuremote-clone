cmake_minimum_required(VERSION 3.22.1)
project(uuremote_gvpb)

set(CMAKE_CXX_STANDARD 17)

# core 与三端共用：直接编译 core/src，include core/include
set(CORE_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../../core)

add_library(gvpb SHARED
    gvpb_jni.cpp
    ${CORE_ROOT}/src/gvpb.cpp
    ${CORE_ROOT}/src/schema.cpp
    ${CORE_ROOT}/src/kcp.cpp
    ${CORE_ROOT}/src/fec.cpp
)

target_include_directories(gvpb PRIVATE
    ${CORE_ROOT}/include
)

find_library(log-lib log)
target_link_libraries(gvpb ${log-lib})
