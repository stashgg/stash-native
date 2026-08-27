#include "StashDesktopJson.h"

#include <cmath>
#include <cstdio>
#include <cstring>

namespace stash {
namespace desktop {
namespace json {

namespace {

bool isSpace(char c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

size_t skipSpace(const std::string &s, size_t i) {
    while (i < s.size() && isSpace(s[i])) {
        i++;
    }
    return i;
}

void appendUtf8(std::string &out, unsigned int code) {
    if (code < 0x80) {
        out += static_cast<char>(code);
    } else if (code < 0x800) {
        out += static_cast<char>(0xC0 | (code >> 6));
        out += static_cast<char>(0x80 | (code & 0x3F));
    } else if (code < 0x10000) {
        out += static_cast<char>(0xE0 | (code >> 12));
        out += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (code & 0x3F));
    } else {
        out += static_cast<char>(0xF0 | (code >> 18));
        out += static_cast<char>(0x80 | ((code >> 12) & 0x3F));
        out += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (code & 0x3F));
    }
}

bool hex4(const std::string &s, size_t i, unsigned int &out) {
    if (i + 4 > s.size()) {
        return false;
    }
    unsigned int value = 0;
    for (size_t k = 0; k < 4; k++) {
        char c = s[i + k];
        unsigned int digit;
        if (c >= '0' && c <= '9') {
            digit = static_cast<unsigned int>(c - '0');
        } else if (c >= 'a' && c <= 'f') {
            digit = static_cast<unsigned int>(c - 'a' + 10);
        } else if (c >= 'A' && c <= 'F') {
            digit = static_cast<unsigned int>(c - 'A' + 10);
        } else {
            return false;
        }
        value = value * 16 + digit;
    }
    out = value;
    return true;
}

// Recursive-descent validation of one JSON value starting at s[i]: returns the index just past
// it, npos on any grammar defect (bad literal, malformed number, invalid escape, unbalanced or
// trailing-comma container). Nesting is capped so hostile input cannot exhaust the stack.
const int kMaxDepth = 64;

size_t skipValueAt(const std::string &s, size_t i, int depth);

bool isDigit(char c) {
    return c >= '0' && c <= '9';
}

size_t skipString(const std::string &s, size_t i) {
    i++;
    while (i < s.size()) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        if (c == '"') {
            return i + 1;
        }
        if (c == '\\') {
            if (i + 1 >= s.size()) {
                return std::string::npos;
            }
            char e = s[i + 1];
            if (e == 'u') {
                unsigned int code = 0;
                if (!hex4(s, i + 2, code)) {
                    return std::string::npos;
                }
                i += 6;
            } else if (e == '"' || e == '\\' || e == '/' || e == 'b' || e == 'f' || e == 'n' || e == 'r' || e == 't') {
                i += 2;
            } else {
                return std::string::npos;
            }
            continue;
        }
        if (c < 0x20) {
            return std::string::npos;
        }
        i++;
    }
    return std::string::npos;
}

size_t skipNumber(const std::string &s, size_t i) {
    if (i < s.size() && s[i] == '-') {
        i++;
    }
    if (i >= s.size()) {
        return std::string::npos;
    }
    if (s[i] == '0') {
        i++;
    } else if (isDigit(s[i])) {
        while (i < s.size() && isDigit(s[i])) {
            i++;
        }
    } else {
        return std::string::npos;
    }
    if (i < s.size() && s[i] == '.') {
        i++;
        size_t digits = i;
        while (i < s.size() && isDigit(s[i])) {
            i++;
        }
        if (i == digits) {
            return std::string::npos;
        }
    }
    if (i < s.size() && (s[i] == 'e' || s[i] == 'E')) {
        i++;
        if (i < s.size() && (s[i] == '+' || s[i] == '-')) {
            i++;
        }
        size_t digits = i;
        while (i < s.size() && isDigit(s[i])) {
            i++;
        }
        if (i == digits) {
            return std::string::npos;
        }
    }
    return i;
}

// Value of a token that matched the JSON number grammar. Hand-rolled because strtod follows
// the process LC_NUMERIC, and a game may have selected a decimal-comma locale.
double parseNumber(const std::string &raw) {
    size_t i = 0;
    bool negative = false;
    if (i < raw.size() && raw[i] == '-') {
        negative = true;
        i++;
    }
    double value = 0;
    while (i < raw.size() && isDigit(raw[i])) {
        value = value * 10 + (raw[i] - '0');
        i++;
    }
    if (i < raw.size() && raw[i] == '.') {
        i++;
        double scale = 0.1;
        while (i < raw.size() && isDigit(raw[i])) {
            value += (raw[i] - '0') * scale;
            scale *= 0.1;
            i++;
        }
    }
    if (i < raw.size() && (raw[i] == 'e' || raw[i] == 'E')) {
        i++;
        int sign = 1;
        if (i < raw.size() && (raw[i] == '+' || raw[i] == '-')) {
            sign = raw[i] == '-' ? -1 : 1;
            i++;
        }
        int exponent = 0;
        while (i < raw.size() && isDigit(raw[i])) {
            if (exponent < 400) {
                exponent = exponent * 10 + (raw[i] - '0');
            }
            i++;
        }
        value *= std::pow(10.0, sign * exponent);
    }
    return negative ? -value : value;
}

size_t skipLiteral(const std::string &s, size_t i, const char *word) {
    size_t n = std::strlen(word);
    return s.compare(i, n, word) == 0 ? i + n : std::string::npos;
}

size_t skipContainer(const std::string &s, size_t i, char close, int depth) {
    if (depth > kMaxDepth) {
        return std::string::npos;
    }
    bool object = close == '}';
    i = skipSpace(s, i + 1);
    if (i < s.size() && s[i] == close) {
        return i + 1;
    }
    while (true) {
        if (object) {
            if (i >= s.size() || s[i] != '"') {
                return std::string::npos;
            }
            i = skipString(s, i);
            if (i == std::string::npos) {
                return std::string::npos;
            }
            i = skipSpace(s, i);
            if (i >= s.size() || s[i] != ':') {
                return std::string::npos;
            }
            i++;
        }
        i = skipValueAt(s, i, depth + 1);
        if (i == std::string::npos) {
            return std::string::npos;
        }
        i = skipSpace(s, i);
        if (i >= s.size()) {
            return std::string::npos;
        }
        if (s[i] == close) {
            return i + 1;
        }
        if (s[i] != ',') {
            return std::string::npos;
        }
        i = skipSpace(s, i + 1);
    }
}

size_t skipValueAt(const std::string &s, size_t i, int depth) {
    i = skipSpace(s, i);
    if (i >= s.size()) {
        return std::string::npos;
    }
    char c = s[i];
    if (c == '"') {
        return skipString(s, i);
    }
    if (c == '{') {
        return skipContainer(s, i, '}', depth);
    }
    if (c == '[') {
        return skipContainer(s, i, ']', depth);
    }
    if (c == 't') {
        return skipLiteral(s, i, "true");
    }
    if (c == 'f') {
        return skipLiteral(s, i, "false");
    }
    if (c == 'n') {
        return skipLiteral(s, i, "null");
    }
    if (c == '-' || isDigit(c)) {
        return skipNumber(s, i);
    }
    return std::string::npos;
}

// Walks one complete top-level object: string keys, colon, fully validated values, commas
// between pairs, nothing but whitespace after the closing brace. False on the first defect, so a
// truncated or garbled object never yields a partial read. With a key, the raw text of its first
// occurrence lands in rawOut and found reports whether it was present.
bool scanObject(const std::string &s, const std::string *key, std::string *rawOut, bool &found) {
    found = false;
    size_t i = skipSpace(s, 0);
    if (i >= s.size() || s[i] != '{') {
        return false;
    }
    i = skipSpace(s, i + 1);
    if (i < s.size() && s[i] == '}') {
        return skipSpace(s, i + 1) == s.size();
    }
    while (true) {
        if (i >= s.size() || s[i] != '"') {
            return false;
        }
        size_t keyEnd = skipString(s, i);
        if (keyEnd == std::string::npos) {
            return false;
        }
        std::string k = unescape(s.substr(i + 1, keyEnd - i - 2));
        i = skipSpace(s, keyEnd);
        if (i >= s.size() || s[i] != ':') {
            return false;
        }
        i = skipSpace(s, i + 1);
        size_t valueEnd = skipValueAt(s, i, 1);
        if (valueEnd == std::string::npos) {
            return false;
        }
        if (key != nullptr && !found && k == *key) {
            found = true;
            if (rawOut != nullptr) {
                *rawOut = s.substr(i, valueEnd - i);
            }
        }
        i = skipSpace(s, valueEnd);
        if (i >= s.size()) {
            return false;
        }
        if (s[i] == '}') {
            return skipSpace(s, i + 1) == s.size();
        }
        if (s[i] != ',') {
            return false;
        }
        i = skipSpace(s, i + 1);
    }
}

}  // namespace

bool isObject(const std::string &text) {
    bool found = false;
    return scanObject(text, nullptr, nullptr, found);
}

bool getRaw(const std::string &object, const std::string &key, std::string &rawOut) {
    bool found = false;
    std::string raw;
    if (!scanObject(object, &key, &raw, found) || !found) {
        return false;
    }
    rawOut = raw;
    return true;
}

bool has(const std::string &object, const std::string &key) {
    std::string raw;
    return getRaw(object, key, raw);
}

std::string getString(const std::string &object, const std::string &key, const std::string &fallback) {
    std::string raw;
    if (!getRaw(object, key, raw) || raw.size() < 2 || raw[0] != '"') {
        return fallback;
    }
    return unescape(raw.substr(1, raw.size() - 2));
}

bool getBool(const std::string &object, const std::string &key, bool fallback) {
    std::string raw;
    if (!getRaw(object, key, raw)) {
        return fallback;
    }
    if (raw == "true") {
        return true;
    }
    if (raw == "false") {
        return false;
    }
    return fallback;
}

double getNumber(const std::string &object, const std::string &key, double fallback) {
    std::string raw;
    if (!getRaw(object, key, raw) || raw.empty()) {
        return fallback;
    }
    char first = raw[0];
    if (!(first == '-' || isDigit(first))) {
        return fallback;
    }
    // getRaw validated the token against the number grammar.
    return parseNumber(raw);
}

std::string escape(const std::string &text) {
    std::string out;
    out.reserve(text.size() + 8);
    for (unsigned char c : text) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned int>(c));
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
        }
    }
    return out;
}

std::string unescape(const std::string &raw) {
    std::string out;
    out.reserve(raw.size());
    for (size_t i = 0; i < raw.size(); i++) {
        if (raw[i] != '\\' || i + 1 >= raw.size()) {
            out += raw[i];
            continue;
        }
        i++;
        switch (raw[i]) {
            case 'n': out += '\n'; break;
            case 'r': out += '\r'; break;
            case 't': out += '\t'; break;
            case 'b': out += '\b'; break;
            case 'f': out += '\f'; break;
            case 'u': {
                unsigned int code = 0;
                if (!hex4(raw, i + 1, code)) {
                    break;
                }
                i += 4;
                // Surrogate pair -> one code point.
                if (code >= 0xD800 && code <= 0xDBFF && i + 6 < raw.size() && raw[i + 1] == '\\' && raw[i + 2] == 'u') {
                    unsigned int low = 0;
                    if (hex4(raw, i + 3, low) && low >= 0xDC00 && low <= 0xDFFF) {
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                        i += 6;
                    }
                }
                // A lone surrogate (WebView2 serializes unpaired JavaScript surrogates as \udXXX)
                // has no UTF-8 form, and U+0000 would truncate the C string handed to the ABI
                // callback; both become U+FFFD.
                if ((code >= 0xD800 && code <= 0xDFFF) || code == 0) {
                    code = 0xFFFD;
                }
                appendUtf8(out, code);
                break;
            }
            default: out += raw[i]; break;
        }
    }
    return out;
}

std::string quote(const std::string &text) {
    return "\"" + escape(text) + "\"";
}

std::string object(const std::vector<std::pair<std::string, std::string>> &fields) {
    std::string out = "{";
    for (size_t i = 0; i < fields.size(); i++) {
        if (i > 0) {
            out += ",";
        }
        out += quote(fields[i].first);
        out += ":";
        out += quote(fields[i].second);
    }
    out += "}";
    return out;
}

std::string dataToPayload(const std::string &rawValue) {
    if (rawValue.empty() || rawValue == "null") {
        return "";
    }
    if (rawValue.size() >= 2 && rawValue[0] == '"' && rawValue[rawValue.size() - 1] == '"') {
        return unescape(rawValue.substr(1, rawValue.size() - 2));
    }
    return rawValue;
}

}  // namespace json
}  // namespace desktop
}  // namespace stash
