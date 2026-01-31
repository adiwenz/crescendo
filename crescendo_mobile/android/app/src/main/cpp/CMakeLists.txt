cmake_minimum_required(VERSION 3.18.1)
project(duplex_engine)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

FetchContent_Declare(
  oboe
  GIT_REPOSITORY https://github.com/google/oboe.git
  GIT_TAG        1.8.1
)
FetchContent_MakeAvailable(oboe)

add_library(duplex_engine SHARED
  duplex_engine.cpp
  ring_buffer.h
)

find_library(log-lib log)

target_link_libraries(duplex_engine
  oboe
  ${log-lib}
  android
)
