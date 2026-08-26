# Win32 sample for the Windows desktop host. Console subsystem on purpose: the -stash-auto proof
# runs print STASH-PROOF lines to stdout for CI and humans. The sample window is the host window
# the card is presented over.
add_executable(StashNativeDesktopSample
    src/main.cpp
    src/SampleWindow.cpp
    src/StashHmac.cpp
    src/LinkGenerator.cpp
    src/ProofRunner.cpp
)
target_include_directories(StashNativeDesktopSample PRIVATE src)
file(TO_CMAKE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../shared/test-pages" STASH_TEST_PAGES_DIR)
target_compile_definitions(StashNativeDesktopSample PRIVATE UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN
    STASH_TEST_PAGES_DIR="${STASH_TEST_PAGES_DIR}")
target_compile_options(StashNativeDesktopSample PRIVATE ${STASH_WIN_WARNINGS} /EHsc)
target_link_libraries(StashNativeDesktopSample PRIVATE StashNativeDesktop user32 gdi32 shell32 advapi32 winhttp bcrypt crypt32)
add_custom_command(TARGET StashNativeDesktopSample POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:StashNativeDesktop> $<TARGET_FILE_DIR:StashNativeDesktopSample>)
