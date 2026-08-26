#include "Sample.hpp"

#include <winhttp.h>

namespace sample {

const char *environmentTitle(Environment env) {
    switch (env) {
        case Environment::Production: return "Production (api.stash.gg)";
        case Environment::Staging: return "Staging (test-api.stashstaging.com)";
        default: return "Test (test-api.stash.gg)";
    }
}

const char *environmentApiBase(Environment env) {
    switch (env) {
        case Environment::Production: return "api.stash.gg";
        case Environment::Staging: return "test-api.stashstaging.com";
        default: return "test-api.stash.gg";
    }
}

// No platform: the enum only knows IOS / ANDROID and desktop is correctly UNDEFINED. Saved payment
// methods are keyed by user id, so reusing this id shows the returning-player preselect.
const char *const kDefaultCheckoutPayload =
    "{\n"
    "  \"user\": {\n"
    "    \"id\": \"7849fbc5-87fd-446d-8d9c-de25298f1092\",\n"
    "    \"validatedEmail\": \"test@stash.gg\",\n"
    "    \"displayName\": \"Test User\"\n"
    "  },\n"
    "  \"item\": {\n"
    "    \"id\": \"realMoneyProduct_gems_001\",\n"
    "    \"name\": \"Handful of Blackstone\",\n"
    "    \"pricePerItem\": \"1.99\",\n"
    "    \"quantity\": 1,\n"
    "    \"imageUrl\": \"https://static.stash.gg/stash_logo_128.png\"\n"
    "  },\n"
    "  \"currency\": \"USD\",\n"
    "  \"createPaymentIntent\": true,\n"
    "  \"regionCode\": \"US\"\n"
    "}\n";

static std::string extractUrlField(const std::string &json) {
    size_t key = json.find("\"url\"");
    if (key == std::string::npos) {
        return "";
    }
    size_t quote = json.find('"', json.find(':', key) + 1);
    if (quote == std::string::npos) {
        return "";
    }
    size_t end = json.find('"', quote + 1);
    if (end == std::string::npos) {
        return "";
    }
    return json.substr(quote + 1, end - quote - 1);
}

bool generateCheckoutUrl(const Settings &settings, const std::string &payload, std::string &urlOut, std::string &errorOut) {
    std::string signature;
    if (!hmacSignature(settings.appId, settings.ingressSecret, payload, signature)) {
        errorOut = "Ingress secret is not valid base64";
        return false;
    }
    HINTERNET session = WinHttpOpen(L"StashNativeDesktopSample/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME,
                                    WINHTTP_NO_PROXY_BYPASS, 0);
    if (session == nullptr) {
        errorOut = "WinHttpOpen failed";
        return false;
    }
    std::wstring host = widen(environmentApiBase(settings.environment));
    HINTERNET connection = WinHttpConnect(session, host.c_str(), INTERNET_DEFAULT_HTTPS_PORT, 0);
    HINTERNET request = connection != nullptr
        ? WinHttpOpenRequest(connection, L"POST", L"/sdk/server/checkout_links/generate_quick_pay_url", nullptr,
                             WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE)
        : nullptr;
    bool ok = false;
    std::string body;
    DWORD statusCode = 0;
    if (request != nullptr) {
        std::wstring headers = L"Content-Type: application/json\r\nx-stash-hmac-signature: " + widen(signature) + L"\r\n";
        ok = WinHttpSendRequest(request, headers.c_str(), static_cast<DWORD>(-1), const_cast<char *>(payload.data()),
                                static_cast<DWORD>(payload.size()), static_cast<DWORD>(payload.size()), 0) != FALSE &&
             WinHttpReceiveResponse(request, nullptr) != FALSE;
        if (ok) {
            DWORD size = sizeof(statusCode);
            WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, WINHTTP_HEADER_NAME_BY_INDEX,
                                &statusCode, &size, WINHTTP_NO_HEADER_INDEX);
            DWORD available = 0;
            while (WinHttpQueryDataAvailable(request, &available) && available > 0) {
                std::string chunk(available, '\0');
                DWORD read = 0;
                if (!WinHttpReadData(request, &chunk[0], available, &read)) {
                    break;
                }
                body.append(chunk, 0, read);
            }
        }
    }
    if (request != nullptr) {
        WinHttpCloseHandle(request);
    }
    if (connection != nullptr) {
        WinHttpCloseHandle(connection);
    }
    WinHttpCloseHandle(session);

    if (!ok) {
        errorOut = "Request failed (WinHTTP error " + std::to_string(GetLastError()) + ")";
        return false;
    }
    if (statusCode < 200 || statusCode >= 300) {
        errorOut = "Server returned HTTP " + std::to_string(statusCode);
        return false;
    }
    std::string url = extractUrlField(body);
    if (url.empty()) {
        errorOut = "Response had no url field";
        return false;
    }
    urlOut = url;
    return true;
}

}  // namespace sample
