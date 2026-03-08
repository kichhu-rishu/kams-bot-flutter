cmake_minimum_required(VERSION 3.22.1)
project(llama_jni)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -fno-finite-math-only")

# llama.cpp sources
file(GLOB LLAMA_SOURCES
    llama.cpp/src/*.cpp
    llama.cpp/src/*.c
    llama.cpp/ggml/src/*.cpp
    llama.cpp/ggml/src/*.c
    llama.cpp/ggml/src/ggml-cpu/*.cpp
    llama.cpp/ggml/src/ggml-cpu/*.c
)

add_library(llama_jni SHARED
    llama_jni.cpp
    ${LLAMA_SOURCES}
)

target_include_directories(llama_jni PRIVATE
    llama.cpp/include
    llama.cpp/ggml/include
    llama.cpp/src
)

find_library(log-lib log)
target_link_libraries(llama_jni ${log-lib} android)
