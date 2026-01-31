cmake_minimum_required(VERSION 3.4.1)

# Fetch Oboe
include(FetchContent)
FetchContent_Declare(
    oboe
    GIT_REPOSITORY https://github.com/google/oboe
    GIT_TAG        1.8.1
)
FetchContent_MakeAvailable(oboe)

add_library(one_clock_engine SHARED duplex_engine.cpp)

target_link_libraries(one_clock_engine
    oboe
    log
    OpenSLES
    atomic
    m
    android
)
