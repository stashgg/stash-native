# Shared desktop contract: pure C++17, no platform headers. Built into both OS hosts and
# unit-tested on its own (test-desktop-shared in lint.yml).
cmake_minimum_required(VERSION 3.16)
project(StashNativeDesktopShared CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(stash_desktop_shared STATIC
    StashDesktopConfig.cpp
    StashDesktopJson.cpp
    StashDesktopSession.cpp
    StashDesktopTheme.cpp
    StashDesktopUrl.cpp
)
target_include_directories(stash_desktop_shared PUBLIC ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/../include)
if(MSVC)
    target_compile_options(stash_desktop_shared PRIVATE /W3 /WX /utf-8)
else()
    target_compile_options(stash_desktop_shared PRIVATE -Wall -Wextra -Werror -pedantic)
endif()

option(STASH_DESKTOP_SHARED_TESTS "Build the shared contract tests" ON)
if(STASH_DESKTOP_SHARED_TESTS)
    enable_testing()
    add_executable(stash_desktop_shared_tests tests/StashDesktopSharedTests.cpp)
    target_link_libraries(stash_desktop_shared_tests PRIVATE stash_desktop_shared)
    if(MSVC)
        target_compile_options(stash_desktop_shared_tests PRIVATE /W3 /WX /utf-8)
    else()
        target_compile_options(stash_desktop_shared_tests PRIVATE -Wall -Wextra -Werror -pedantic)
    endif()
    add_test(NAME stash_desktop_shared_tests COMMAND stash_desktop_shared_tests)
endif()
