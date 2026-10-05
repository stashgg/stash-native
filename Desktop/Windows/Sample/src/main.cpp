// Win32 sample for the Windows desktop host. Run it for the interactive window, or
// StashNativeDesktopSample.exe -stash-auto <local|remote|secure> [-stash-url <url>] for a proof run.

#include "Sample.hpp"

#include <cstring>

static std::string argumentValue(int argc, char **argv, const char *name) {
    for (int i = 1; i + 1 < argc; i++) {
        if (std::strcmp(argv[i], name) == 0) {
            return argv[i + 1];
        }
    }
    return "";
}

int main(int argc, char **argv) {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    HINSTANCE instance = GetModuleHandleW(nullptr);
    HWND window = sample::createSampleWindow(instance);
    stash::StashNativeCard::getInstance().prewarm();

    std::string mode = argumentValue(argc, argv, "-stash-auto");
    if (!mode.empty()) {
        sample::startProof(mode, argumentValue(argc, argv, "-stash-url"), window);
    }

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    return 0;
}
