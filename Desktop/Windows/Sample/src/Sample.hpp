// Shared declarations of the Windows sample.
#ifndef STASH_SAMPLE_HPP
#define STASH_SAMPLE_HPP

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <functional>
#include <string>
#include <vector>

#include "StashNativeCard.hpp"

namespace sample {

std::wstring widen(const std::string &utf8);
std::string narrow(const std::wstring &utf16);

// -- Settings (HKCU\Software\Stash\StashNativeDesktopSample) ----------------------------------
// The ingress secret is session-only: a server secret must never ship in a real client, so the
// sample never writes it to the registry and removes a value an earlier build stored there.

enum class Environment { Test, Production, Staging };

struct Settings {
    std::string appId;
    std::string ingressSecret;
    Environment environment = Environment::Test;
    std::string lastUrl;

    static Settings load();
    void save() const;
};

const char *environmentTitle(Environment env);
const char *environmentApiBase(Environment env);
extern const char *const kDefaultCheckoutPayload;

// -- HMAC (StashHmac.cpp) ----------------------------------------------------------------------

// x-stash-hmac-signature: v1;<appId>;<unixMillis>;<base64 HMAC-SHA256 of "<unixMillis>." + body>
// with the base64-decoded ingress secret as the key. In a real integration this belongs on the
// backend; the sample signs in-process so the flow can be exercised locally.
bool hmacSignature(const std::string &appId, const std::string &ingressSecretB64, const std::string &body, std::string &out);

// -- Link generation (LinkGenerator.cpp) ------------------------------------------------------

// POST /sdk/server/checkout_links/generate_quick_pay_url, synchronous (WinHTTP). Returns the
// generated URL or an error message.
bool generateCheckoutUrl(const Settings &settings, const std::string &payload, std::string &urlOut, std::string &errorOut);

// -- Event log ---------------------------------------------------------------------------------

struct EventEntry {
    std::string type;
    std::string payload;

    // What the window shows and the proof runner prints. Payloads can carry the checkout URL
    // (navigation) or order data (paymentSuccess): only safe fields are rendered, the rest by size.
    std::string summary() const;
};

// scheme://host of a URL, "" when it has no scheme.
std::string urlOrigin(const std::string &url);

class EventLog {
public:
    static EventLog &shared();
    void install();
    std::vector<std::string> types() const;
    const std::vector<EventEntry> &entries() const { return entries_; }
    void clear() { entries_.clear(); }
    std::function<void(const EventEntry &)> onEvent;
    std::vector<EventEntry> entries_;
};

// -- Proof runner (ProofRunner.cpp) ------------------------------------------------------------

// file:// URL of an offline test page: next to the executable when packaged, else the source tree.
std::string testPageUrl(const char *name);
void startProof(const std::string &mode, const std::string &remoteUrl, HWND hostWindow);

// -- Window (SampleWindow.cpp) ----------------------------------------------------------------

HWND createSampleWindow(HINSTANCE instance);

}  // namespace sample

#endif
