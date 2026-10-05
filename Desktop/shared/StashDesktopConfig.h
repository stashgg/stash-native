// Config JSON contract of the desktop hosts and the desktop sizing rule. Pure C++, unit-tested.
//
// Seven keys: autoClose, allowDismiss, backgroundColor, allowFileUrls, presentation, width and
// height. Missing keys take the defaults below. Unknown keys are ignored (wrappers may still send
// mobile fields). Anything that is not one complete JSON object yields all defaults.
#ifndef STASH_DESKTOP_CONFIG_H
#define STASH_DESKTOP_CONFIG_H

#include <string>

namespace stash {
namespace desktop {

enum class Presentation { Attached, Window };

struct SurfaceConfig {
    bool autoClose = true;
    // When false the user's dismiss paths (close button, backdrop, Escape, standalone window close)
    // are refused; the page's window.close and the host's Dismiss still close.
    bool allowDismiss = true;
    // Trimmed HTML hex or "" for the default theme.
    std::string backgroundColor;

    // Desktop-only keys, set by wrappers.
    Presentation presentation = Presentation::Attached;
    double width = 0;   // points; 0 = 480 x 720 default
    double height = 0;
    bool allowFileUrls = false;
};

// Parses the config JSON. NULL / empty / malformed JSON yields the defaults.
SurfaceConfig parseSurfaceConfig(const std::string &json);

// Desktop sizing rule, all values in points (DPI-independent).
const double kCardDefaultWidth = 480;
const double kCardDefaultHeight = 720;
// Smallest card the checkout is laid out for; a smaller explicit width or height is raised to it.
const double kMinSurfaceWidth = 400;
const double kMinSurfaceHeight = 500;
// Space kept between the card and the host client edges.
const double kHostMargin = 24;
// Never below this even in a tiny host window.
const double kAbsoluteFloorWidth = 200;
const double kAbsoluteFloorHeight = 240;

struct SurfaceSize {
    double width;
    double height;
};

// Explicit width / height when set, else the 480 x 720 default; raised to the minimum; then clamped to
// the host client area minus the margin (the margin wins over the minimum, down to the absolute
// floor). Host dimensions <= 0 mean "no host" (window presentation): no clamp.
SurfaceSize resolveSurfaceSize(const SurfaceConfig &config, double hostClientWidth, double hostClientHeight);

// Load-failure policy shared by both hosts (same policy as the mobile SDKs).
const double kStallRetrySeconds = 1.25;
const int kMaxStallReloads = 2;
const double kNetworkDeadlineSeconds = 15.0;

}  // namespace desktop
}  // namespace stash

#endif
