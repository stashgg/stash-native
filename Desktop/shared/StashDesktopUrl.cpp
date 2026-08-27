#include "StashDesktopUrl.h"

namespace stash {
namespace desktop {
namespace url {

namespace {

bool isSchemeChar(char c, bool first) {
    bool alpha = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
    if (first) {
        return alpha;
    }
    return alpha || (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.';
}

bool startsWith(const std::string &s, const char *prefix) {
    return s.compare(0, std::char_traits<char>::length(prefix), prefix) == 0;
}

bool containsControlOrSpace(const std::string &s) {
    for (unsigned char c : s) {
        if (c <= 0x20 || c == 0x7F) {
            return true;
        }
    }
    return false;
}

bool validHostChars(const std::string &h) {
    for (unsigned char c : h) {
        bool ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_' ||
                  c == '[' || c == ']' || c == ':' || c == '%' || c >= 0x80;
        if (!ok) {
            return false;
        }
    }
    return true;
}

}  // namespace

std::string trim(const std::string &s) {
    size_t start = 0;
    while (start < s.size() && (s[start] == ' ' || s[start] == '\t' || s[start] == '\r' || s[start] == '\n')) {
        start++;
    }
    size_t end = s.size();
    while (end > start && (s[end - 1] == ' ' || s[end - 1] == '\t' || s[end - 1] == '\r' || s[end - 1] == '\n')) {
        end--;
    }
    return s.substr(start, end - start);
}

std::string toLower(std::string s) {
    for (char &c : s) {
        if (c >= 'A' && c <= 'Z') {
            c = static_cast<char>(c - 'A' + 'a');
        }
    }
    return s;
}

std::string scheme(const std::string &u) {
    size_t colon = u.find(':');
    if (colon == std::string::npos || colon == 0) {
        return "";
    }
    for (size_t i = 0; i < colon; i++) {
        if (!isSchemeChar(u[i], i == 0)) {
            return "";
        }
    }
    return toLower(u.substr(0, colon));
}

// Authority of a hierarchical URL with the userinfo removed; "" when there is no "://".
static std::string authority(const std::string &u) {
    size_t start = u.find("://");
    if (start == std::string::npos) {
        return "";
    }
    start += 3;
    size_t end = u.find_first_of("/?#", start);
    std::string auth = u.substr(start, end == std::string::npos ? std::string::npos : end - start);
    size_t at = auth.rfind('@');
    if (at != std::string::npos) {
        auth = auth.substr(at + 1);
    }
    return auth;
}

// Host and port of an authority. False when a bracketed IPv6 literal is unterminated or the
// port is not 1-5 digits within 0..65535 ("host:" counts as no port).
static bool splitAuthority(const std::string &auth, std::string &hostOut, std::string &portOut) {
    portOut.clear();
    std::string rest;
    if (!auth.empty() && auth[0] == '[') {
        size_t close = auth.find(']');
        if (close == std::string::npos) {
            hostOut = auth;
            return false;
        }
        hostOut = auth.substr(0, close + 1);
        rest = auth.substr(close + 1);
        if (!rest.empty() && rest[0] != ':') {
            return false;
        }
    } else {
        size_t colon = auth.find(':');
        hostOut = colon == std::string::npos ? auth : auth.substr(0, colon);
        rest = colon == std::string::npos ? "" : auth.substr(colon);
    }
    if (rest.empty()) {
        return true;
    }
    portOut = rest.substr(1);
    if (portOut.size() > 5) {
        return false;
    }
    for (char c : portOut) {
        if (c < '0' || c > '9') {
            return false;
        }
    }
    return portOut.empty() || std::stoi(portOut) <= 65535;
}

std::string host(const std::string &u) {
    std::string h;
    std::string port;
    splitAuthority(authority(u), h, port);
    return toLower(h);
}

std::string origin(const std::string &u) {
    std::string sch = scheme(u);
    if (sch.empty()) {
        return "";
    }
    if (u.compare(sch.size(), 3, "://") != 0) {
        return sch + ":";
    }
    std::string h;
    std::string port;
    splitAuthority(authority(u), h, port);
    return sch + "://" + toLower(h) + (port.empty() ? "" : ":" + port);
}

bool isWebScheme(const std::string &u) {
    std::string s = scheme(trim(u));
    return s.empty() || s == "http" || s == "https" || s == "about" || s == "data" || s == "blob" ||
           s == "file" || s == "javascript";
}

DeeplinkResult classifyDeeplinkResult(const std::string &u) {
    std::string lower = toLower(u);
    if (lower.find("stash-pay/success") != std::string::npos) {
        return DeeplinkResult::Success;
    }
    if (lower.find("stash-pay/failure") != std::string::npos) {
        return DeeplinkResult::Failure;
    }
    if (lower.find("stash-pay/cancel") != std::string::npos) {
        return DeeplinkResult::Cancel;
    }
    return DeeplinkResult::None;
}

bool normalizeExternalPaymentUrl(const std::string &raw, std::string &out) {
    std::string s = trim(raw);
    if (s.empty()) {
        return false;
    }
    std::string lower = toLower(s);
    if (startsWith(lower, "javascript:") || startsWith(lower, "file:") || startsWith(lower, "data:")) {
        return false;
    }
    if (!startsWith(lower, "http://") && !startsWith(lower, "https://")) {
        s = "https://" + s;
    }
    // A URL parser would reject these; mobile returns nil / null for them.
    if (containsControlOrSpace(s)) {
        return false;
    }
    std::string sch = scheme(s);
    if (sch != "http" && sch != "https") {
        return false;
    }
    // The whole authority must parse: a bad port ("host:bogus") would close the checkout for a
    // handoff the browser cannot use.
    std::string h;
    std::string port;
    if (!splitAuthority(authority(s), h, port)) {
        return false;
    }
    h = toLower(h);
    if (h.empty() || !validHostChars(h)) {
        return false;
    }
    out = s;
    return true;
}

std::string stripThemeQueryParameter(const std::string &u) {
    size_t hash = u.find('#');
    std::string fragment = hash != std::string::npos ? u.substr(hash) : "";
    std::string head = hash != std::string::npos ? u.substr(0, hash) : u;
    size_t q = head.find('?');
    if (q == std::string::npos) {
        return u;
    }
    std::string path = head.substr(0, q);
    std::string query = head.substr(q + 1);
    std::string kept;
    size_t pos = 0;
    while (pos <= query.size()) {
        size_t amp = query.find('&', pos);
        std::string segment = query.substr(pos, amp == std::string::npos ? std::string::npos : amp - pos);
        if (!segment.empty()) {
            size_t eq = segment.find('=');
            std::string key = eq != std::string::npos ? segment.substr(0, eq) : segment;
            if (key != "theme") {
                if (!kept.empty()) {
                    kept += '&';
                }
                kept += segment;
            }
        }
        if (amp == std::string::npos) {
            break;
        }
        pos = amp + 1;
    }
    std::string rebuilt = kept.empty() ? path : path + "?" + kept;
    return rebuilt + fragment;
}

std::string appendThemeQueryParameter(const std::string &u, bool dark) {
    if (u.empty()) {
        return u;
    }
    std::string base = stripThemeQueryParameter(u);
    const char *theme = dark ? "dark" : "light";
    size_t hash = base.find('#');
    std::string fragment = hash != std::string::npos ? base.substr(hash) : "";
    std::string head = hash != std::string::npos ? base.substr(0, hash) : base;
    std::string separator = head.find('?') != std::string::npos ? "&" : "?";
    return head + separator + "theme=" + theme + fragment;
}

bool isRedirectStatus(int statusCode) {
    return statusCode == 301 || statusCode == 302 || statusCode == 303 || statusCode == 307 || statusCode == 308;
}

}  // namespace url
}  // namespace desktop
}  // namespace stash
