#include "StashDesktopWebMessage.hpp"

#include "StashDesktopJson.h"

namespace stash {
namespace desktop {
namespace win {

bool parseWebMessage(const std::string &text, std::string &typeOut, std::string &payloadOut) {
    std::string json = text;
    size_t start = json.find_first_not_of(" \t\r\n");
    if (start != std::string::npos && json[start] == '"') {
        size_t end = json.find_last_of('"');
        if (end != std::string::npos && end > start) {
            std::string inner = stash::desktop::json::unescape(json.substr(start + 1, end - start - 1));
            if (stash::desktop::json::isObject(inner)) {
                json = inner;
            }
        }
    }
    if (!stash::desktop::json::isObject(json)) {
        return false;
    }
    std::string type = stash::desktop::json::getString(json, "type", "");
    if (type.empty()) {
        return false;
    }
    std::string raw;
    std::string payload;
    if (stash::desktop::json::getRaw(json, "data", raw)) {
        payload = stash::desktop::json::dataToPayload(raw);
    }
    typeOut = type;
    payloadOut = payload;
    return true;
}

std::wstring userDataFolderFor(const std::wstring &localAppData, const std::wstring &executablePath) {
    std::wstring name = executablePath;
    size_t slash = name.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
        name = name.substr(slash + 1);
    }
    size_t dot = name.find_last_of(L'.');
    if (dot != std::wstring::npos && dot > 0) {
        name = name.substr(0, dot);
    }
    if (name.empty()) {
        name = L"Game";
    }
    // Per install, not per basename: two titles whose executables are both Game.exe must not
    // share (or contend for) one profile. FNV-1a over the case-folded full path is stable for
    // the lifetime of an install and changes only when the game moves.
    unsigned long long hash = 1469598103934665603ULL;
    for (wchar_t c : executablePath) {
        wchar_t folded = (c >= L'A' && c <= L'Z') ? static_cast<wchar_t>(c + 32) : (c == L'/' ? L'\\' : c);
        hash ^= static_cast<unsigned long long>(folded);
        hash *= 1099511628211ULL;
    }
    wchar_t suffix[24];
    swprintf_s(suffix, 24, L"-%08x", static_cast<unsigned int>(hash ^ (hash >> 32)));
    std::wstring base = localAppData.empty() ? std::wstring(L".") : localAppData;
    if (!base.empty() && (base.back() == L'\\' || base.back() == L'/')) {
        base.pop_back();
    }
    return base + L"\\Stash\\" + name + suffix + L"\\WebView2";
}

}  // namespace win
}  // namespace desktop
}  // namespace stash
