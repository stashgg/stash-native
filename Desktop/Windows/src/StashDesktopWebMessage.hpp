// Parses the {type, data} objects the WebView2 shim posts through chrome.webview.postMessage.
// Pure C++ so the Windows tests can pin it.
#ifndef STASH_DESKTOP_WEB_MESSAGE_HPP
#define STASH_DESKTOP_WEB_MESSAGE_HPP

#include <string>

namespace stash {
namespace desktop {
namespace win {

// WebMessageAsJson text -> message name and coerced payload (string values unquoted, objects as
// JSON text, missing data as ""). A pre-stringified message (a JSON string holding an object) is
// unwrapped one level. False when there is no type.
bool parseWebMessage(const std::string &json, std::string &typeOut, std::string &payloadOut);

// %LOCALAPPDATA%\Stash\<executable name>-<hash of the executable path>\WebView2: one WebView2
// profile per installed game, so same-named executables of different titles never share one.
std::wstring userDataFolderFor(const std::wstring &localAppData, const std::wstring &executablePath);

}  // namespace win
}  // namespace desktop
}  // namespace stash

#endif
