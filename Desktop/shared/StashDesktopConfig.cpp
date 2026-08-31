#include "StashDesktopConfig.h"

#include <cmath>

#include "StashDesktopJson.h"
#include "StashDesktopUrl.h"

namespace stash {
namespace desktop {

double clampRatio(double v) {
    if (!(v >= 0.1)) {
        return 0.1;
    }
    if (v > 1.0) {
        return 1.0;
    }
    return v;
}

namespace {

double ratio(const std::string &json, const char *key, double fallback) {
    return clampRatio(json::getNumber(json, key, fallback));
}

double dimension(const std::string &json, const char *key) {
    double v = json::getNumber(json, key, 0);
    if (!(v > 0) || std::isinf(v)) {
        return 0;
    }
    return v;
}

}  // namespace

SurfaceConfig parseSurfaceConfig(SurfaceMode mode, const std::string &text) {
    SurfaceConfig c;
    c.mode = mode;
    if (!json::isObject(text)) {
        return c;
    }
    c.autoClose = json::getBool(text, "autoClose", true);
    c.backgroundColor = url::trim(json::getString(text, "backgroundColor", ""));
    c.allowFileUrls = json::getBool(text, "allowFileUrls", false);
    c.presentation = json::getString(text, "presentation", "attached") == "window" ? Presentation::Window
                                                                                 : Presentation::Attached;
    c.width = dimension(text, "width");
    c.height = dimension(text, "height");

    if (mode == SurfaceMode::Card) {
        c.allowDismiss = true;
        c.forcePortrait = json::getBool(text, "forcePortrait", false);
        c.cardHeightRatioPortrait = ratio(text, "cardHeightRatioPortrait", c.cardHeightRatioPortrait);
        c.cardWidthRatioLandscape = ratio(text, "cardWidthRatioLandscape", c.cardWidthRatioLandscape);
        c.cardHeightRatioLandscape = ratio(text, "cardHeightRatioLandscape", c.cardHeightRatioLandscape);
        c.tabletWidthRatioPortrait = ratio(text, "tabletWidthRatioPortrait", c.tabletWidthRatioPortrait);
        c.tabletHeightRatioPortrait = ratio(text, "tabletHeightRatioPortrait", c.tabletHeightRatioPortrait);
        c.tabletWidthRatioLandscape = ratio(text, "tabletWidthRatioLandscape", c.tabletWidthRatioLandscape);
        c.tabletHeightRatioLandscape = ratio(text, "tabletHeightRatioLandscape", c.tabletHeightRatioLandscape);
    } else {
        c.allowDismiss = json::getBool(text, "allowDismiss", true);
        c.phoneWidthRatioPortrait = ratio(text, "phoneWidthRatioPortrait", c.phoneWidthRatioPortrait);
        c.phoneHeightRatioPortrait = ratio(text, "phoneHeightRatioPortrait", c.phoneHeightRatioPortrait);
        c.phoneWidthRatioLandscape = ratio(text, "phoneWidthRatioLandscape", c.phoneWidthRatioLandscape);
        c.phoneHeightRatioLandscape = ratio(text, "phoneHeightRatioLandscape", c.phoneHeightRatioLandscape);
        // Modal tablet keys share the card names on mobile; the modal defaults apply here.
        c.modalTabletWidthRatioPortrait = ratio(text, "tabletWidthRatioPortrait", c.modalTabletWidthRatioPortrait);
        c.modalTabletHeightRatioPortrait = ratio(text, "tabletHeightRatioPortrait", c.modalTabletHeightRatioPortrait);
        c.modalTabletWidthRatioLandscape = ratio(text, "tabletWidthRatioLandscape", c.modalTabletWidthRatioLandscape);
        c.modalTabletHeightRatioLandscape = ratio(text, "tabletHeightRatioLandscape", c.modalTabletHeightRatioLandscape);
    }
    return c;
}

SurfaceSize resolveSurfaceSize(const SurfaceConfig &config, double hostClientWidth, double hostClientHeight) {
    bool modal = config.mode == SurfaceMode::Modal;
    double w = config.width > 0 ? config.width : (modal ? kModalDefaultWidth : kCardDefaultWidth);
    double h = config.height > 0 ? config.height : (modal ? kModalDefaultHeight : kCardDefaultHeight);
    if (w < kMinSurfaceWidth) {
        w = kMinSurfaceWidth;
    }
    if (h < kMinSurfaceHeight) {
        h = kMinSurfaceHeight;
    }
    if (hostClientWidth > 0 && hostClientHeight > 0) {
        double maxW = hostClientWidth - 2 * kHostMargin;
        double maxH = hostClientHeight - 2 * kHostMargin;
        if (maxW < kAbsoluteFloorWidth) {
            maxW = kAbsoluteFloorWidth;
        }
        if (maxH < kAbsoluteFloorHeight) {
            maxH = kAbsoluteFloorHeight;
        }
        if (w > maxW) {
            w = maxW;
        }
        if (h > maxH) {
            h = maxH;
        }
    }
    return SurfaceSize{w, h};
}

}  // namespace desktop
}  // namespace stash
