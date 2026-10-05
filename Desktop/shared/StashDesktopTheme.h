// Background colour parsing and the light / dark decision: a custom backgroundColor's luminance
// wins over the system appearance. Same algorithm as the mobile SDKs.
#ifndef STASH_DESKTOP_THEME_H
#define STASH_DESKTOP_THEME_H

#include <cstdint>
#include <string>

namespace stash {
namespace desktop {
namespace theme {

const uint32_t kDarkBackgroundArgb = 0xFF1E1E1E;
const uint32_t kLightBackgroundArgb = 0xFFFFFFFF;
// Backdrop dim, 40% black on every mode and OS.
const double kOverlayDimAlpha = 0.4;

// #RGB, #RRGGBB, #AARRGGBB (leading '#' optional, case-insensitive, trimmed) -> ARGB.
// #RGB and #RRGGBB are opaque; #AARRGGBB keeps its alpha. False when invalid.
bool parseHexColor(const std::string &hex, uint32_t &argbOut);

// Relative luminance (sRGB linearised) below 0.5. Alpha is ignored.
bool isDarkColor(uint32_t argb);

// The colour behind the checkout: the custom colour when valid, else the system default.
uint32_t cardBackgroundArgb(const std::string &backgroundColor, bool systemPrefersDark);

// Dark vs light for theme= and the web content: custom colour luminance if valid, else system.
bool effectiveThemeIsDark(const std::string &backgroundColor, bool systemPrefersDark);

// "#RRGGBB" (upper case), alpha dropped.
std::string cssHex(uint32_t argb);

// Script that pins html/body to the card colour and dark color-scheme.
std::string darkCardScript(uint32_t cardArgb);

}  // namespace theme
}  // namespace desktop
}  // namespace stash

#endif
