#include "StashDesktopConfig.h"

#include <cmath>

#include "StashDesktopJson.h"
#include "StashDesktopUrl.h"

namespace stash {
namespace desktop {

namespace {

double dimension(const std::string &json, const char *key) {
    double v = json::getNumber(json, key, 0);
    if (!(v > 0) || std::isinf(v)) {
        return 0;
    }
    return v;
}

}  // namespace

SurfaceConfig parseSurfaceConfig(const std::string &text) {
    SurfaceConfig c;
    if (!json::isObject(text)) {
        return c;
    }
    c.autoClose = json::getBool(text, "autoClose", true);
    c.allowDismiss = json::getBool(text, "allowDismiss", true);
    c.backgroundColor = url::trim(json::getString(text, "backgroundColor", ""));
    c.allowFileUrls = json::getBool(text, "allowFileUrls", false);
    c.presentation = json::getString(text, "presentation", "attached") == "window" ? Presentation::Window
                                                                                 : Presentation::Attached;
    c.width = dimension(text, "width");
    c.height = dimension(text, "height");
    return c;
}

SurfaceSize resolveSurfaceSize(const SurfaceConfig &config, double hostClientWidth, double hostClientHeight) {
    double w = config.width > 0 ? config.width : kCardDefaultWidth;
    double h = config.height > 0 ? config.height : kCardDefaultHeight;
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
