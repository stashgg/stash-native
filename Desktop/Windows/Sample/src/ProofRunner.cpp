// -stash-auto <local|remote|secure>: hands-free proof runs for CI and humans. Prints
// "STASH-PROOF <mode>: RESULT: PASS|FAIL" and exits with 0 / 1.
//
//   local   offline test page over the sample window, expects the full bridge round trip
//   remote  -stash-url <https://...>: the page must load (navigation, pageLoaded)
//   secure  file:// without allowFileUrls and http:// are both refused with the checkout closed

#include "Sample.hpp"

#include <cstdio>
#include <cstdlib>

namespace sample {

namespace {

const UINT_PTR kProofTimeoutTimer = 77;
const UINT kProofTimeoutMs = 25000;

struct Proof {
    std::string mode;
    std::string remoteUrl;
    HWND host = nullptr;
    int phase = 0;
};

Proof g_proof;

void log(const std::string &line) {
    std::printf("STASH-PROOF %s: %s\n", g_proof.mode.c_str(), line.c_str());
    std::fflush(stdout);
}

std::string join(const std::vector<std::string> &items) {
    std::string out;
    for (size_t i = 0; i < items.size(); i++) {
        if (i > 0) {
            out += " -> ";
        }
        out += items[i];
    }
    return out;
}

void finish(bool pass, const std::string &detail) {
    log("RESULT: " + std::string(pass ? "PASS" : "FAIL") + " (" + detail + ")");
    log("events: " + join(EventLog::shared().types()));
    StashNativeDesktop_Shutdown();
    std::exit(pass ? 0 : 1);
}

void evaluateSecure(const std::vector<std::string> &types, bool presented) {
    size_t offset = static_cast<size_t>((g_proof.phase - 1) * 2);
    if (types.size() < offset + 2) {
        return;
    }
    bool passed = types[offset] == "navigationBlocked" && types[offset + 1] == "networkError" && !presented;
    if (!passed) {
        finish(false, "phase " + std::to_string(g_proof.phase) + " expected navigationBlocked -> networkError");
        return;
    }
    if (g_proof.phase == 1) {
        g_proof.phase = 2;
        log("phase 1 ok: file:// refused; opening http://example.com");
        stash::StashNativeCard::getInstance().openCard("http://example.com/");
    } else {
        finish(true, "file:// and http:// refused, checkout never presented");
    }
}

// Adjacent navigation entries collapse into one (a redirect chain reports several); every other
// event stays, so duplicates cannot pass as the expected sequence.
std::vector<std::string> collapsedTypes() {
    std::vector<std::string> out;
    for (const std::string &type : EventLog::shared().types()) {
        if (type == "navigation" && !out.empty() && out.back() == "navigation") {
            continue;
        }
        out.push_back(type);
    }
    return out;
}

void evaluate() {
    std::vector<std::string> types = collapsedTypes();
    bool presented = stash::StashNativeCard::getInstance().isCurrentlyPresented();
    if (g_proof.mode == "local") {
        std::vector<std::string> expected = {"navigation", "pageLoaded", "purchaseProcessing", "paymentSuccess"};
        if (types.size() >= expected.size()) {
            bool passed = std::vector<std::string>(types.begin(), types.begin() + static_cast<long>(expected.size())) == expected &&
                          !presented;
            finish(passed, passed ? "bridge round trip completed, checkout closed" : "unexpected sequence");
        } else {
            for (const std::string &t : types) {
                if (t == "networkError") {
                    finish(false, "network error");
                }
            }
        }
    } else if (g_proof.mode == "remote") {
        for (const std::string &t : types) {
            if (t == "pageLoaded") {
                bool passed = !types.empty() && types[0] == "navigation" && presented;
                stash::StashNativeCard::getInstance().dismiss();
                finish(passed, "checkout loaded");
            }
            if (t == "networkError") {
                finish(false, "network error");
            }
        }
    } else if (g_proof.mode == "secure") {
        evaluateSecure(types, presented);
    }
}

void CALLBACK onTimeout(HWND, UINT, UINT_PTR, DWORD) {
    finish(false, "timeout after " + std::to_string(kProofTimeoutMs / 1000) + "s");
}

}  // namespace

std::string testPageUrl(const char *name) {
    wchar_t module[MAX_PATH] = L"";
    DWORD length = GetModuleFileNameW(nullptr, module, MAX_PATH);
    std::string dir;
    if (length > 0 && length < MAX_PATH) {
        std::string exe = narrow(module);
        size_t slash = exe.find_last_of("\\/");
        std::string packaged = exe.substr(0, slash == std::string::npos ? 0 : slash) + "\\test-pages";
        if (GetFileAttributesW(widen(packaged).c_str()) != INVALID_FILE_ATTRIBUTES) {
            dir = packaged;
        }
    }
    if (dir.empty()) {
        dir = STASH_TEST_PAGES_DIR;
    }
    for (char &c : dir) {
        if (c == '\\') {
            c = '/';
        }
    }
    return "file:///" + dir + "/" + name;
}

void startProof(const std::string &mode, const std::string &remoteUrl, HWND hostWindow) {
    g_proof.mode = mode;
    g_proof.remoteUrl = remoteUrl;
    g_proof.host = hostWindow;
    EventLog::shared().onEvent = [](const EventEntry &entry) {
        log("event " + entry.summary());
        evaluate();
    };
    SetTimer(hostWindow, kProofTimeoutTimer, kProofTimeoutMs, onTimeout);
    stash::StashNativeCard &card = stash::StashNativeCard::getInstance();
    if (mode == "local") {
        std::string url = testPageUrl("stash_test_checkout.html") + "?auto=1";
        log("opening stash_test_checkout.html?auto=1 with allowFileUrls");
        card.openCard(url, std::string("{\"allowFileUrls\":true}"));
    } else if (mode == "remote") {
        if (remoteUrl.empty()) {
            finish(false, "pass -stash-url <https://checkout url>");
        }
        // The generated link carries a signed token: name the origin only.
        log("opening " + urlOrigin(remoteUrl));
        card.openCard(remoteUrl);
    } else if (mode == "secure") {
        g_proof.phase = 1;
        std::string url = testPageUrl("stash_test_checkout.html");
        log("opening stash_test_checkout.html without allowFileUrls");
        card.openCard(url);
    } else {
        finish(false, "unknown mode, use local | remote | secure");
    }
}

}  // namespace sample
