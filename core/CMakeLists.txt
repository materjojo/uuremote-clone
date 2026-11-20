cmake_minimum_required(VERSION 3.16)
project(gvpb LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(GVPB_SOURCES
    src/gvpb.cpp
    src/schema.cpp
    src/kcp.cpp
    src/fec.cpp
    ../native/official/official_streamer_abi.cpp
)

# Compile the common sources once; both libraries consume the same object files.
add_library(gvpb_objects OBJECT ${GVPB_SOURCES})
target_include_directories(gvpb_objects PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${CMAKE_CURRENT_SOURCE_DIR}/../native/official/include)
set_target_properties(gvpb_objects PROPERTIES POSITION_INDEPENDENT_CODE ON)

# 静态库：三端单测与可执行文件链接
add_library(gvpb STATIC $<TARGET_OBJECTS:gvpb_objects>)
target_include_directories(gvpb PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include ${CMAKE_CURRENT_SOURCE_DIR}/../native/official/include)

# 共享库：给 Windows P/Invoke（gvpb.dll）与 Android JNI（libgvpb.so）共用同一实现
add_library(gvpb_shared SHARED $<TARGET_OBJECTS:gvpb_objects>)
target_include_directories(gvpb_shared PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include ${CMAKE_CURRENT_SOURCE_DIR}/../native/official/include)
set_target_properties(gvpb_shared PROPERTIES OUTPUT_NAME gvpb WINDOWS_EXPORT_ALL_SYMBOLS ON)
if(WIN32)
    # Keep the DLL import library separate from the static gvpb.lib test target.
    set_target_properties(gvpb_shared PROPERTIES ARCHIVE_OUTPUT_NAME gvpb_import)
endif()

add_executable(gvpb_tests tests/test_core.cpp)
target_link_libraries(gvpb_tests PRIVATE gvpb)
# Release must execute assertions: many legacy test operations are inside assert().
if(MSVC)
    target_compile_options(gvpb_tests PRIVATE /UNDEBUG)
else()
    target_compile_options(gvpb_tests PRIVATE -UNDEBUG)
endif()

enable_testing()
add_test(NAME gvpb_core COMMAND gvpb_tests)
