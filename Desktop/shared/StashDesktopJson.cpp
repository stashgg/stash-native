#include "StashDesktopJson.h"

#include <cstdio>
#include <cstdlib>

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

// Index just past the value starting at s[i]; npos on malformed input.
size_t skipValue(const std::string &s, size_t i) {
    i = skipSpace(s, i);
    if (i >= s.size()) {
        return std::string::npos;
    }
    char c = s[i];
    if (c == '"') {
        i++;
        while (i < s.size()) {
            if (s[i] == '\\') {
                i += 2;
                continue;
            }
            if (s[i] == '"') {
                return i + 1;
            }
            i++;
        }
        return std::string::npos;
    }
    if (c == '{' || c == '[') {
        int depth = 0;
        bool inString = false;
        while (i < s.size()) {
            char d = s[i];
            if (inString) {
                if (d == '\\') {
                    i += 2;
                    continue;
                }
                if (d == '"') {
                    inString = false;
                }
            } else if (d == '"') {
                inString = true;
            } else if (d == '{' || d == '[') {
                depth++;
            } else if (d == '}' || d == ']') {
                depth--;
                if (depth == 0) {
                    return i + 1;
                }
            }
            i++;
        }
        return std::string::npos;
    }
    while (i < s.size() && s[i] != ',' && s[i] != '}' && s[i] != ']' && !isSpace(s[i])) {
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

}  // namespace

bool isObject(const std::string &text) {
    size_t i = skipSpace(text, 0);
    return i < text.size() && text[i] == '{';
}

bool getRaw(const std::string &object, const std::string &key, std::string &rawOut) {
    size_t i = skipSpace(object, 0);
    if (i >= object.size() || object[i] != '{') {
        return false;
    }
    i++;
    while (i < object.size()) {
        while (i < object.size() && (isSpace(object[i]) || object[i] == ',')) {
            i++;
        }
        if (i >= object.size() || object[i] == '}') {
            return false;
        }
        if (object[i] != '"') {
            return false;
        }
        size_t keyEnd = skipValue(object, i);
        if (keyEnd == std::string::npos) {
            return false;
        }
        std::string k = unescape(object.substr(i + 1, keyEnd - i - 2));
        i = skipSpace(object, keyEnd);
        if (i >= object.size() || object[i] != ':') {
            return false;
        }
        i = skipSpace(object, i + 1);
        size_t valueEnd = skipValue(object, i);
        if (valueEnd == std::string::npos) {
            return false;
        }
        if (k == key) {
            rawOut = object.substr(i, valueEnd - i);
            return true;
        }
        i = valueEnd;
    }
    return false;
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
    if (!(first == '-' || (first >= '0' && first <= '9'))) {
        return fallback;
    }
    char *end = nullptr;
    double value = std::strtod(raw.c_str(), &end);
    if (end == raw.c_str() || (end != nullptr && *end != '\0')) {
        return fallback;
    }
    return value;
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
