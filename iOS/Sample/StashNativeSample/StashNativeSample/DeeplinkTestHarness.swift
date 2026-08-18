//
//  DeeplinkTestHarness.swift
//  StashNativeSample
//
//  A self-contained page that exercises every deeplink path the SDK's checkout
//  WebView handles. It is loaded into the card as a base64 data: URL so no server
//  or bundled file is needed. The deeplink target is this sample app itself, via
//  its registered stashdemo:// scheme (see Info.plist / StashSampleDeepLink).
//

import Foundation

// Long lines below are HTML markup kept readable as a single block.
// swiftlint:disable line_length
enum DeeplinkTestHarness {

    /// Custom URL scheme this sample registers; used as the "installed app" target.
    static let appScheme = "stashdemo"

    /// Card content: buttons/links for each deeplink scenario. Anchor taps are
    /// LinkActivated navigations, which is what the SDK's universal-link path requires.
    static let html = """
    <!doctype html>
    <html>
    <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
    <meta name="color-scheme" content="light only">
    <style>
      body { font: -apple-system-body, system-ui, sans-serif; margin: 0; padding: 20px 16px;
             background: #fff; color: #111; }
      h1 { font-size: 20px; margin: 0 0 4px; }
      p.sub { color: #666; font-size: 13px; margin: 0 0 20px; }
      h2 { font-size: 13px; text-transform: uppercase; color: #888; margin: 22px 0 8px; }
      a.btn, button.btn {
        display: block; width: 100%; box-sizing: border-box; text-align: left;
        text-decoration: none; border: 0; border-radius: 12px; padding: 14px 16px;
        margin: 8px 0; font-size: 16px; background: #007aff; color: #fff; }
      a.btn.alt, button.btn.alt { background: #eef0f4; color: #111; }
      a.btn small, button.btn small { display: block; font-size: 12px; opacity: .8; margin-top: 3px; }
      #log { margin-top: 16px; font-size: 12px; color: #444; white-space: pre-wrap; }
      iframe { display: none; }
    </style>
    </head>
    <body>
      <h1>Deeplink test harness</h1>
      <p class="sub">Each action navigates out of the checkout WebView. The target is this sample app (stashdemo://). Watch for the callback chip after returning.</p>

      <h2>App link (installed)</h2>
      <a class="btn" href="stashdemo://deeplink-test?scenario=custom-scheme">Custom scheme deeplink<small>stashdemo://deeplink-test</small></a>
      <button class="btn" onclick="viaIframe('stashdemo://deeplink-test?scenario=iframe')">Deeplink from an iframe<small>sub-frame navigation, must still be intercepted</small></button>

      <h2>Android intent://</h2>
      <a class="btn alt" href="intent://deeplink-test?scenario=intent#Intent;scheme=stashdemo;package=com.stash.stashnative.sample;end">Intent URI to this app<small>intent://...;scheme=stashdemo;package=...;end</small></a>

      <h2>iOS universal link</h2>
      <a class="btn alt" href="https://example.com/deeplink-test">Universal link (https)<small>needs associated domains; falls back to loading in card</small></a>

      <h2>App not installed / fallback</h2>
      <a class="btn alt" href="stashunknown://nope">Unhandled custom scheme<small>no app: handled gracefully, card stays open</small></a>
      <a class="btn alt" href="intent://nope#Intent;scheme=stashunknown;package=com.example.notinstalled;S.browser_fallback_url=https%3A%2F%2Fexample.com%2Ffallback;end">Intent with browser_fallback_url<small>Android: opens the https fallback</small></a>
      <a class="btn alt" href="intent://nope#Intent;scheme=stashunknown;package=com.example.notinstalled;end">Intent, missing app, no fallback<small>Android: opens the Play Store listing</small></a>

      <h2>stash-pay result signals</h2>
      <a class="btn alt" href="stashdemo://stash-pay/success">Simulate payment success<small>runs the SDK success flow, closes the card</small></a>
      <a class="btn alt" href="stashdemo://stash-pay/cancel">Simulate cancel<small>closes the card</small></a>

      <div id="log"></div>
      <iframe id="frame"></iframe>
      <script>
        function viaIframe(u) {
          document.getElementById('log').textContent = 'iframe -> ' + u;
          document.getElementById('frame').src = u;
        }
      </script>
    </body>
    </html>
    """

    /// The harness as a data: URL the card can load offline.
    static func dataURL() -> String {
        let base64 = Data(html.utf8).base64EncodedString()
        return "data:text/html;base64,\(base64)"
    }
}
// swiftlint:enable line_length
