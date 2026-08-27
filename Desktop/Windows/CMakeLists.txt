# Windows host of Stash Native desktop payments: StashNativeDesktop.dll (WebView2), the tests
# and (from a later PR) the Win32 sample. Requires Visual Studio 2019/2022 with the C++ workload.
#
#   cmake -S Desktop/Windows -B Desktop/Windows/build -A x64
#   cmake --build Desktop/Windows/build --config Release
#
# The WebView2 SDK is fetched from NuGet at configure time (latest by default, pin with
# -DSTASH_WEBVIEW2_VERSION=<version>) into the build directory; WebView2LoaderStatic.lib is
# linked so one DLL ships. Static CRT (/MT) so players need no VC redistributable.
cmake_minimum_required(VERSION 3.20)
project(StashNativeDesktop CXX)

if(NOT WIN32)
    message(FATAL_ERROR "Desktop/Windows builds on Windows only; Desktop/shared has the portable tests")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

set(STASH_WEBVIEW2_VERSION "" CACHE STRING "Microsoft.Web.WebView2 NuGet version (empty = latest)")
set(STASH_WEBVIEW2_DIR "${CMAKE_BINARY_DIR}/webview2")
if(NOT EXISTS "${STASH_WEBVIEW2_DIR}/build/native/include/WebView2.h")
    if(STASH_WEBVIEW2_VERSION STREQUAL "")
        set(_webview2_url "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2")
    else()
        set(_webview2_url "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/${STASH_WEBVIEW2_VERSION}")
    endif()
    message(STATUS "Fetching WebView2 SDK from ${_webview2_url}")
    file(DOWNLOAD "${_webview2_url}" "${CMAKE_BINARY_DIR}/webview2.nupkg" STATUS _download_status)
    list(GET _download_status 0 _download_code)
    if(NOT _download_code EQUAL 0)
        message(FATAL_ERROR "WebView2 SDK download failed: ${_download_status}")
    endif()
    file(ARCHIVE_EXTRACT INPUT "${CMAKE_BINARY_DIR}/webview2.nupkg" DESTINATION "${STASH_WEBVIEW2_DIR}")
endif()
set(STASH_WEBVIEW2_INCLUDE "${STASH_WEBVIEW2_DIR}/build/native/include")
set(STASH_WEBVIEW2_LOADER "${STASH_WEBVIEW2_DIR}/build/native/x64/WebView2LoaderStatic.lib")

set(STASH_DESKTOP_SHARED_TESTS ON CACHE BOOL "" FORCE)
# At the project root, or ctest at the build root finds no tests at all.
enable_testing()
add_subdirectory(../shared shared)

set(STASH_WIN_WARNINGS /W3 /WX /utf-8)

add_library(StashNativeDesktop SHARED
    src/StashDesktopWebMessage.cpp
    src/StashNativeCard.cpp
    src/StashNativeCardWebView.cpp
    src/StashNativeCardWindow.cpp
    src/StashNativeDesktopExports.cpp
)
target_include_directories(StashNativeDesktop
    PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../include ${CMAKE_CURRENT_SOURCE_DIR}/include
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src ${STASH_WEBVIEW2_INCLUDE}
)
target_compile_definitions(StashNativeDesktop PRIVATE STASH_NATIVE_DESKTOP_BUILDING UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN)
target_compile_options(StashNativeDesktop PRIVATE ${STASH_WIN_WARNINGS} /EHsc)
target_link_libraries(StashNativeDesktop PRIVATE stash_desktop_shared "${STASH_WEBVIEW2_LOADER}"
    user32 gdi32 ole32 shell32 shlwapi advapi32 uuid version)
set_target_properties(StashNativeDesktop PROPERTIES OUTPUT_NAME "StashNativeDesktop" PREFIX "")

# Windows-side parity checks plus a compile of the header-only facade against the import library.
add_executable(StashNativeDesktopTests tests/StashNativeDesktopTests.cpp src/StashDesktopWebMessage.cpp)
target_include_directories(StashNativeDesktopTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_definitions(StashNativeDesktopTests PRIVATE UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN)
target_compile_options(StashNativeDesktopTests PRIVATE ${STASH_WIN_WARNINGS} /EHsc)
target_link_libraries(StashNativeDesktopTests PRIVATE StashNativeDesktop stash_desktop_shared)
add_test(NAME StashNativeDesktopTests COMMAND StashNativeDesktopTests)

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/Sample/CMakeLists.txt")
    add_subdirectory(Sample)
endif()
