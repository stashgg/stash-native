// Config JSON contract of the desktop hosts and the desktop sizing rule. Pure C++, unit-tested.
//
// Keys use the mobile field names verbatim (StashNativeCardConfig / StashNativeModalConfig) so
// wrappers serialize their existing structs. Missing keys take the mobile defaults, unknown keys
// are ignored. Ratios are parsed and clamped to [0.1, 1.0] for parity but ignored for sizing:
// the card is a fixed logical size on desktop (see resolveSurfaceSize).
#ifndef STASH_DESKTOP_CONFIG_H
#define STASH_DESKTOP_CONFIG_H

#include <string>

namespace stash {
namespace desktop {

enum class SurfaceMode { Card, Modal };
enum class Presentation { Attached, Window };

struct SurfaceConfig {
    SurfaceMode mode = SurfaceMode::Card;
    bool autoClose = true;
    // Modal only. Cards are always user-dismissable.
    bool allowDismiss = true;
    // Accepted for parity, no effect on desktop.
    bool forcePortrait = false;
    // Trimmed HTML hex or "" for the default theme.
    std::string backgroundColor;

    // Desktop-only keys, set by wrappers.
    Presentation presentation = Presentation::Attached;
    double width = 0;   // points; 0 = mode default
    double height = 0;
    bool allowFileUrls = false;

    // Card ratios (mobile defaults).
    double cardHeightRatioPortrait = 0.68;
    double cardWidthRatioLandscape = 0.7;
    double cardHeightRatioLandscape = 0.9;
    double tabletWidthRatioPortrait = 0.4;
    double tabletHeightRatioPortrait = 0.5;
    double tabletWidthRatioLandscape = 0.3;
    double tabletHeightRatioLandscape = 0.6;
    // Modal ratios (mobile defaults).
    double phoneWidthRatioPortrait = 0.80;
    double phoneHeightRatioPortrait = 0.50;
    double phoneWidthRatioLandscape = 0.50;
    double phoneHeightRatioLandscape = 0.80;
    double modalTabletWidthRatioPortrait = 0.40;
    double modalTabletHeightRatioPortrait = 0.30;
    double modalTabletWidthRatioLandscape = 0.30;
    double modalTabletHeightRatioLandscape = 0.40;
};

// [0.1, 1.0]; NaN and anything below 0.1 become 0.1 (iOS stashClampRatio).
double clampRatio(double v);

// Parses the config JSON for the given mode. NULL / empty / malformed JSON yields the defaults.
SurfaceConfig parseSurfaceConfig(SurfaceMode mode, const std::string &json);

// Desktop sizing rule, all values in points (DPI-independent).
const double kCardDefaultWidth = 480;
const double kCardDefaultHeight = 720;
const double kModalDefaultWidth = 480;
const double kModalDefaultHeight = 600;
// Mobile tablet minimum.
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

// Explicit width / height when set, else the mode default; raised to the minimum; then clamped to
// the host client area minus the margin (the margin wins over the minimum, down to the absolute
// floor). Host dimensions <= 0 mean "no host" (window presentation): no clamp.
SurfaceSize resolveSurfaceSize(const SurfaceConfig &config, double hostClientWidth, double hostClientHeight);

// Load-failure policy shared by both hosts (mobile parity).
const double kStallRetrySeconds = 1.25;
const int kMaxStallReloads = 2;
const double kNetworkDeadlineSeconds = 15.0;

}  // namespace desktop
}  // namespace stash

#endif
