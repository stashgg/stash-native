package com.stash.stashnative;

import android.webkit.WebView;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONObject;

/** Card-only content measurement, scoped to a committed document and its CSS viewport. */
final class StashContentSizeSupport {
  private final StashCheckoutActivity activity;
  private String documentId;
  private String navigationUrl;
  private int reportSequence;
  private boolean disposed;

  StashContentSizeSupport(StashCheckoutActivity activity) {
    this.activity = activity;
  }

  void navigationStarted(String url) {
    documentId = null;
    navigationUrl = url;
    reportSequence++;
    activity.presentation.clearContent();
  }

  void documentCommitted(WebView view, String url) {
    if (disposed
        || view != activity.webView
        || url == null
        || !url.equals(view.getUrl())
        || (navigationUrl != null && !navigationUrl.equals(url))) {
      return;
    }
    if (documentId == null) {
      documentId = UUID.randomUUID().toString();
    }
    view.evaluateJavascript(script(documentId), null);
  }

  void widthChanged() {
    reportSequence++;
    if (activity.webView != null) {
      activity.webView.post(
          () -> {
            if (!disposed && activity.webView != null) {
              activity.webView.evaluateJavascript(
                  "window.__stashMeasureContent&&window.__stashMeasureContent()", null);
            }
          });
    }
  }

  void accept(String payload) {
    if (disposed || documentId == null || activity.webView == null || activity.isDismissing) {
      return;
    }
    try {
      JSONObject message = new JSONObject(payload);
      boolean reset = Boolean.TRUE.equals(message.opt("reset"));
      if (!(message.get("documentId") instanceof String)
          || (!reset && !(message.get("height") instanceof Number))
          || !(message.get("viewportWidth") instanceof Number)
          || !(message.get("scale") instanceof Number)) {
        return;
      }
      String token = message.getString("documentId");
      double height = reset ? 0 : message.getDouble("height");
      double width = message.getDouble("viewportWidth");
      double scale = message.getDouble("scale");
      if (!token.equals(documentId)
          || (!reset && !valid(height))
          || !valid(width)
          || !valid(scale)
          || Math.abs(scale - 1) > 0.01) {
        return;
      }
      WebView web = activity.webView;
      int nativeWidth = web.getWidth();
      if (nativeWidth <= 0) {
        return;
      }
      int sequence = ++reportSequence;
      web.evaluateJavascript(
          "[window.innerWidth,window.visualViewport?window.visualViewport.scale:1,"
              + "window.__stashContentDocumentId]",
          value -> {
            if (disposed
                || sequence != reportSequence
                || web != activity.webView
                || !token.equals(documentId)
                || nativeWidth != web.getWidth()) {
              return;
            }
            try {
              JSONArray current = new JSONArray(value);
              if (!valid(current.getDouble(0))
                  || !valid(current.getDouble(1))
                  || !token.equals(current.getString(2))
                  || Math.abs(current.getDouble(0) - width) > 1
                  || Math.abs(current.getDouble(1) - scale) > 0.01) {
                return;
              }
              double pixels = height * nativeWidth / width;
              if (reset) {
                activity.presentation.clearContent();
              } else if (valid(pixels)) {
                activity.presentation.contentChanged(pixels, nativeWidth);
              }
            } catch (Exception expected) {
              // The committed document may have changed before evaluation completes.
            }
          });
    } catch (Exception expected) {
      // A malformed page hint must not affect the current presentation.
    }
  }

  private static boolean valid(double value) {
    return !Double.isNaN(value) && !Double.isInfinite(value) && value > 0;
  }

  void dispose() {
    disposed = true;
    documentId = null;
    reportSequence++;
  }

  static String script(String id) {
    return "(function () {"
        + "  if (window !== window.top) return;"
        + "  if (window.__stashMeasureCleanup) window.__stashMeasureCleanup();"
        + "  var id = "
        + JSONObject.quote(id)
        + ", sdk = window.stash_sdk = window.stash_sdk || {};"
        + "  var observed = null, ro = null, mo = null, pending = false, dispos"
        + "ed = false, last = '', lastSource = '';"
        + "  window.__stashContentDocumentId = id;"
        + "  function send(height, source) {"
        + "    var width = window.innerWidth, scale = window.visualViewport ? w"
        + "indow.visualViewport.scale : 1;"
        + "    if (disposed || typeof height !== 'number' || !isFinite(height) "
        + "|| height <= 0 ||"
        + "        !isFinite(width) || width <= 0 || !isFinite(scale) || Math.a"
        + "bs(scale - 1) > .01) return;"
        + "    var key = [height, width, scale, source].join(':');"
        + "    lastSource = source;"
        + "    if (key === last) return;"
        + "    last = key;"
        + "    try { StashAndroid.setContentHeight(JSON.stringify({height:heigh"
        + "t,viewportWidth:width,scale:scale,documentId:id})); } catch (error) "
        + "{}"
        + "  }"
        + "  sdk.setContentHeight = function (height) { send(height, 'explicit'"
        + "); };"
        + "  function invalidateObserved() {"
        + "    if (lastSource !== 'observed') return;"
        + "    last = '';"
        + "    lastSource = '';"
        + "    var width = window.innerWidth, scale = window.visualViewport ? w"
        + "indow.visualViewport.scale : 1;"
        + "    if (!isFinite(width) || width <= 0 || !isFinite(scale) || Math.a"
        + "bs(scale - 1) > .01) return;"
        + "    try { StashAndroid.setContentHeight(JSON.stringify({reset:true,v"
        + "iewportWidth:width,scale:scale,documentId:id})); } catch (error) {}"
        + "  }"
        + "  function viewportRule(style) {"
        + "    return /(?:^|[;{])\\s*(?:min-|max-)?(?:height|block-size)\\s*:[^;}"
        + "]*(?:%|(?:d|s|l)?vh|vmin|vmax|cqh|cqb|var\\s*\\()/i.test(style || '');"
        + "  }"
        + "  function eligible(root) {"
        + "    var ancestors = [];"
        + "    for (var element = root; element; element = element.parentElemen"
        + "t) {"
        + "      var style = getComputedStyle(element);"
        + "      if (style.position === 'fixed' || style.position === 'sticky' "
        + "|| style.position === 'absolute' ||"
        + "          (element === root && parseFloat(style.flexGrow) > 0) || vi"
        + "ewportRule(element.getAttribute('style'))) return false;"
        + "      ancestors.push(element);"
        + "    }"
        + "    function rules(list) {"
        + "      for (var index = 0; index < list.length; index++) {"
        + "        var rule = list[index];"
        + "        if (rule.cssRules && !rules(rule.cssRules)) return false;"
        + "        if (rule.selectorText && viewportRule(rule.style && rule.sty"
        + "le.cssText)) {"
        + "          for (var ancestor = 0; ancestor < ancestors.length; ancest"
        + "or++) {"
        + "            if (ancestors[ancestor].matches(rule.selectorText)) retu"
        + "rn false;"
        + "          }"
        + "        }"
        + "      }"
        + "      return true;"
        + "    }"
        + "    try {"
        + "      for (var sheet = 0; sheet < document.styleSheets.length; sheet"
        + "++) {"
        + "        if (!rules(document.styleSheets[sheet].cssRules)) return fal"
        + "se;"
        + "      }"
        + "    } catch (error) { return false; }"
        + "    return true;"
        + "  }"
        + "  function measure() {"
        + "    pending = false;"
        + "    if (disposed) return;"
        + "    var root = document.querySelector('[data-stash-content]');"
        + "    if (root !== observed) {"
        + "      if (ro) ro.disconnect();"
        + "      observed = root;"
        + "      if (root && window.ResizeObserver) {"
        + "        ro = new ResizeObserver(schedule);"
        + "        ro.observe(root);"
        + "      }"
        + "    }"
        + "    if (!root || !eligible(root)) { invalidateObserved(); return; }"
        + "    var style = getComputedStyle(root);"
        + "    send(root.getBoundingClientRect().height + (parseFloat(style.mar"
        + "ginTop) || 0) + (parseFloat(style.marginBottom) || 0), 'observed');"
        + "  }"
        + "  function schedule() {"
        + "    if (!disposed && !pending) { pending = true; requestAnimationFra"
        + "me(measure); }"
        + "  }"
        + "  window.__stashMeasureContent = function () { last = ''; schedule()"
        + "; };"
        + "  if (window.MutationObserver && document.documentElement) {"
        + "    mo = new MutationObserver(schedule);"
        + "    mo.observe(document.documentElement, {subtree: true, childList: "
        + "true, attributes: true, characterData: true});"
        + "  }"
        + "  window.addEventListener('resize', schedule);"
        + "  window.addEventListener('load', schedule);"
        + "  if (document.fonts && document.fonts.ready) document.fonts.ready.t"
        + "hen(schedule);"
        + "  window.__stashMeasureCleanup = function () {"
        + "    disposed = true;"
        + "    if (ro) ro.disconnect();"
        + "    if (mo) mo.disconnect();"
        + "    window.removeEventListener('resize', schedule);"
        + "    window.removeEventListener('load', schedule);"
        + "    sdk.setContentHeight = function () {};"
        + "  };"
        + "  schedule();"
        + "})();";
  }
}
