// URL helpers shared by both desktop hosts. Same algorithms as StashWebViewUtils.java and
// StashNativeCardViewUtils.m / StashNativeCardTheme.m on mobile; pure C++, unit-tested.
#ifndef STASH_DESKTOP_URL_H
#define STASH_DESKTOP_URL_H

#include <string>

namespace stash {
namespace desktop {
namespace url {

std::string trim(const std::string &s);
std::string toLower(std::string s);

// Lowercase scheme, "" when the text has none (or the candidate contains non-scheme characters).
std::string scheme(const std::string &url);
// Lowercase host without userinfo or port, "" when absent. IPv6 literals keep their brackets.
std::string host(const std::string &url);
// "scheme://host[:port]" for hierarchical URLs (the port as written, when present),
// "scheme:" otherwise, "" without a scheme. What the diagnostic events carry instead of a URL:
// a checkout link holds a signed token and wrappers log these payloads.
std::string origin(const std::string &url);

// Loads inside the webview: http, https, about, data, blob, file, javascript, or no scheme
// (relative). Everything else is a deeplink.
bool isWebScheme(const std::string &url);

enum class DeeplinkResult { None, Success, Failure, Cancel };

// stash-pay/success | failure | cancel anywhere in the URL, case-insensitive, any scheme.
DeeplinkResult classifyDeeplinkResult(const std::string &url);

// window.stash_sdk.openExternalBrowser / openLink validation: trims, rejects javascript: /
// file: / data:, prepends https:// when there is no scheme, http/https only, non-empty host.
// False when rejected.
bool normalizeExternalPaymentUrl(const std::string &raw, std::string &out);

// Removes every theme=... query segment (exact key match), keeping order and fragment.
std::string stripThemeQueryParameter(const std::string &url);
// Idempotent: strips existing theme values first, then appends theme=dark|light before the fragment.
std::string appendThemeQueryParameter(const std::string &url, bool dark);

// 301/302/303/307/308 (not 304).
bool isRedirectStatus(int statusCode);

}  // namespace url
}  // namespace desktop
}  // namespace stash

#endif
