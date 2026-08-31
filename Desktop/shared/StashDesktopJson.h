// Minimal JSON reading and writing for the desktop hosts: flat config objects from wrappers and
// {type, data} web messages from the shim. String- and nesting-aware scanner, no dependencies.
#ifndef STASH_DESKTOP_JSON_H
#define STASH_DESKTOP_JSON_H

#include <string>
#include <utility>
#include <vector>

namespace stash {
namespace desktop {
namespace json {

// True when the text is one complete, well-formed JSON object (surrounding whitespace allowed):
// string keys, values validated against the full JSON grammar, nothing after the closing brace. Config and message parsing gate
// on this so a truncated object falls back to defaults instead of a partial read.
bool isObject(const std::string &text);

// Raw value text of a top-level key ("..." for strings, {...} / [...] for containers,
// literal for numbers / true / false / null). False when absent or when the object is malformed
// anywhere, even after the key.
bool getRaw(const std::string &object, const std::string &key, std::string &rawOut);

bool has(const std::string &object, const std::string &key);
std::string getString(const std::string &object, const std::string &key, const std::string &fallback);
bool getBool(const std::string &object, const std::string &key, bool fallback);
double getNumber(const std::string &object, const std::string &key, double fallback);

std::string escape(const std::string &text);
std::string unescape(const std::string &rawWithoutQuotes);
std::string quote(const std::string &text);

// {"k":"v",...} with every value quoted and escaped.
std::string object(const std::vector<std::pair<std::string, std::string>> &fields);

// Payload rule for message data: a JSON string value passes through unquoted, anything else is
// forwarded as its JSON text ("" when absent). Mirrors the shim's onPaymentSuccess coercion for
// hosts that receive the raw {type, data} message (WebView2).
std::string dataToPayload(const std::string &rawValue);

}  // namespace json
}  // namespace desktop
}  // namespace stash

#endif
