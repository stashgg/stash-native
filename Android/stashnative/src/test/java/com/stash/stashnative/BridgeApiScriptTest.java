package com.stash.stashnative;

import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class BridgeApiScriptTest {

  private static final String SCRIPT = StashWebViewUtils.JS_SDK_SCRIPT;

  @Test
  public void scriptDefinesExternalBrowserWithAStrictKeepOpenFlag() {
    assertTrue(SCRIPT.contains("window.stash_sdk.externalBrowser = function(url, options)"));
    assertTrue(SCRIPT.contains("!!(options && options.keepOpen === true)"));
    assertTrue(SCRIPT.contains(".externalBrowser("));
  }

  @Test
  public void scriptKeepsTheOpenExternalBrowserDefinition() {
    assertTrue(
        SCRIPT.contains(
            "window.stash_sdk.openExternalBrowser = function(url) {"
                + "    try { "
                + StashWebViewUtils.JS_INTERFACE_NAME
                + ".openExternalBrowser((url !== undefined && url !== null) ? String(url) : '');"));
  }
}
