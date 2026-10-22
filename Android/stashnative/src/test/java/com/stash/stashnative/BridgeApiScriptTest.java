package com.stash.stashnative;

import static org.junit.Assert.assertTrue;

import org.junit.Test;

/** The injected stash_sdk names, including the aliases kept for older checkout pages. */
public class BridgeApiScriptTest {
  private final String script = StashWebViewUtils.JS_SDK_SCRIPT;

  @Test public void lockAndUnlockAliasTheProcessingCalls() {
    assertTrue(script.contains("window.stash_sdk.lock = window.stash_sdk.onPurchaseProcessing;"));
    assertTrue(script.contains("window.stash_sdk.unlock = window.stash_sdk.onProcessingCompleted;"));
  }

  @Test public void openExternalBrowserForwardsToExternalBrowserWithoutKeepOpen() {
    assertTrue(script.contains("window.stash_sdk.externalBrowser = function(url, options)"));
    assertTrue(script.contains("options === true || !!(options && options.keepOpen === true)"));
    assertTrue(script.contains("window.stash_sdk.externalBrowser(url);"));
  }

  @Test public void triggerHapticPassesTheType() {
    assertTrue(script.contains("type === 1 || type === 'long' ? 'long' : 'short'"));
  }
}
