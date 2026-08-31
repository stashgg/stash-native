#include "StashDesktopTheme.h"

#include <cmath>
#include <cstdio>

#include "StashDesktopUrl.h"
#include "StashSdkScript.h"

namespace stash {
namespace desktop {
namespace theme {

namespace {

bool hexNibble(char c, unsigned int &out) {
    if (c >= '0' && c <= '9') {
        out = static_cast<unsigned int>(c - '0');
        return true;
    }
    if (c >= 'a' && c <= 'f') {
        out = static_cast<unsigned int>(c - 'a' + 10);
        return true;
    }
    if (c >= 'A' && c <= 'F') {
        out = static_cast<unsigned int>(c - 'A' + 10);
        return true;
    }
    return false;
}

bool hexValue(const std::string &s, unsigned long &out) {
    unsigned long value = 0;
    for (char c : s) {
        unsigned int nibble = 0;
        if (!hexNibble(c, nibble)) {
            return false;
        }
        value = value * 16 + nibble;
    }
    out = value;
    return true;
}

double linearize(double c) {
    return (c <= 0.03928) ? (c / 12.92) : std::pow((c + 0.055) / 1.055, 2.4);
}

}  // namespace

bool parseHexColor(const std::string &hex, uint32_t &argbOut) {
    std::string s = url::trim(hex);
    if (s.empty()) {
        return false;
    }
    if (s[0] == '#') {
        s = s.substr(1);
    }
    if (s.size() == 3) {
        unsigned int r = 0, g = 0, b = 0;
        if (!hexNibble(s[0], r) || !hexNibble(s[1], g) || !hexNibble(s[2], b)) {
            return false;
        }
        argbOut = 0xFF000000u | ((r * 17u) << 16) | ((g * 17u) << 8) | (b * 17u);
        return true;
    }
    if (s.size() == 6) {
        unsigned long value = 0;
        if (!hexValue(s, value)) {
            return false;
        }
        argbOut = 0xFF000000u | static_cast<uint32_t>(value);
        return true;
    }
    if (s.size() == 8) {
        unsigned long value = 0;
        if (!hexValue(s, value)) {
            return false;
        }
        argbOut = static_cast<uint32_t>(value);
        return true;
    }
    return false;
}

bool isDarkColor(uint32_t argb) {
    double r = ((argb >> 16) & 0xFF) / 255.0;
    double g = ((argb >> 8) & 0xFF) / 255.0;
    double b = (argb & 0xFF) / 255.0;
    double lum = 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b);
    return lum < 0.5;
}

uint32_t sheetBackgroundArgb(const std::string &backgroundColor, bool systemPrefersDark) {
    uint32_t custom = 0;
    if (parseHexColor(backgroundColor, custom)) {
        return custom;
    }
    return systemPrefersDark ? kDarkBackgroundArgb : kLightBackgroundArgb;
}

bool effectiveThemeIsDark(const std::string &backgroundColor, bool systemPrefersDark) {
    uint32_t custom = 0;
    if (parseHexColor(backgroundColor, custom)) {
        return isDarkColor(custom);
    }
    return systemPrefersDark;
}

std::string cssHex(uint32_t argb) {
    char buf[16];
    std::snprintf(buf, sizeof(buf), "#%02X%02X%02X", (argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
    return buf;
}

std::string darkSheetScript(uint32_t sheetArgb) {
    return std::string(STASH_SDK_DARK_SHEET_SCRIPT_PREFIX) + cssHex(sheetArgb) + STASH_SDK_DARK_SHEET_SCRIPT_SUFFIX;
}

}  // namespace theme
}  // namespace desktop
}  // namespace stash
