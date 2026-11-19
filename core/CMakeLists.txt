cmake_minimum_required(VERSION 3.16)
project(gvpb LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(gvpb STATIC
    src/gvpb.cpp
    src/schema.cpp
    src/kcp.cpp
    src/fec.cpp
)
target_include_directories(gvpb PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)

add_executable(gvpb_tests tests/test_core.cpp)
target_link_libraries(gvpb_tests PRIVATE gvpb)

enable_testing()
add_test(NAME gvpb_core COMMAND gvpb_tests)
