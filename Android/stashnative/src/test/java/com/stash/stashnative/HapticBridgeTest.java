package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Looper;
import android.view.HapticFeedbackConstants;
import android.webkit.WebView;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowLooper;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 30})
@LooperMode(LooperMode.Mode.PAUSED)
public class HapticBridgeTest {
  private StashCardActivity activity;
  private RecordingWebView web;
  private StashCheckoutJsInterface bridge;
  private String token;

  @Before public void prepare() {
    StashNativePlugin plugin = StashNativePlugin.getInstance();
    plugin.resetPresentationState();
    plugin.isCurrentlyPresented = true;
    Intent intent = new Intent().putExtra(StashCheckoutBridge.EXTRA_SESSION_ID,
        plugin.presentationSessionId);
    activity = Robolectric.buildActivity(StashCardActivity.class, intent).get();
    web = new RecordingWebView(activity);
    activity.webView = web;
    bridge = new StashCheckoutJsInterface(activity);
    token = activity.issueBridgeDocumentToken();
  }

  @After public void cleanup() {
    StashNativePlugin.getInstance().resetPresentationState();
    web.destroy();
  }

  @Test public void webThreadDispatchesConfirmationToMainThread() throws Exception {
    Thread caller = new Thread(() -> bridge.triggerHaptic(token));
    caller.start();
    caller.join();
    assertEquals(0, web.calls);
    ShadowLooper.idleMainLooper();
    assertEquals(1, web.calls);
    assertTrue(web.onMainThread);
    assertEquals(Build.VERSION.SDK_INT >= 30
        ? HapticFeedbackConstants.CONFIRM : HapticFeedbackConstants.VIRTUAL_KEY, web.feedback);
  }

  @Test public void longTypePlaysTheHeavierPulseAndOtherValuesStayShort() {
    bridge.triggerHaptic(token, "long");
    ShadowLooper.idleMainLooper();
    assertEquals(Build.VERSION.SDK_INT >= 30
        ? HapticFeedbackConstants.REJECT : HapticFeedbackConstants.LONG_PRESS, web.feedback);
    bridge.triggerHaptic(token, "loud");
    ShadowLooper.idleMainLooper();
    assertEquals(Build.VERSION.SDK_INT >= 30
        ? HapticFeedbackConstants.CONFIRM : HapticFeedbackConstants.VIRTUAL_KEY, web.feedback);
    assertEquals(2, web.calls);
  }

  @Test public void hiddenBackgroundAndClosingCardsIgnoreFeedback() {
    activity.isActivityPaused = true;
    bridge.triggerHaptic(token);
    activity.isActivityPaused = false;
    web.focused = false;
    bridge.triggerHaptic(token);
    web.focused = true;
    web.shown = false;
    bridge.triggerHaptic(token);
    web.shown = true;
    activity.isDismissing = true;
    bridge.triggerHaptic(token);
    activity.isDismissing = false;
    activity.webView = null;
    bridge.triggerHaptic(token);
    assertEquals(0, web.calls);
  }

  @Test public void queuedCallCannotVibrateAfterDismissalStarts() throws Exception {
    Thread caller = new Thread(() -> bridge.triggerHaptic(token));
    caller.start();
    caller.join();
    activity.isDismissing = true;
    ShadowLooper.idleMainLooper();
    assertEquals(0, web.calls);
  }

  @Test public void unavailableFeedbackLeavesPurchaseAndPresentationUntouched() {
    activity.isPurchaseProcessing = true;
    bridge.triggerHaptic(token);
    assertEquals(1, web.calls);
    assertTrue(activity.isPurchaseProcessing);
    assertFalse(activity.isDismissing);
    assertFalse(activity.callbackSent);
  }

  private static final class RecordingWebView extends WebView {
    boolean focused = true;
    boolean shown = true;
    boolean onMainThread;
    int calls;
    int feedback;

    RecordingWebView(Context context) {
      super(context);
    }

    @Override public boolean hasWindowFocus() { return focused; }
    @Override public boolean isShown() { return shown; }

    @Override public boolean performHapticFeedback(int constant) {
      calls++;
      feedback = constant;
      onMainThread = Looper.myLooper() == Looper.getMainLooper();
      return false;
    }
  }
}
