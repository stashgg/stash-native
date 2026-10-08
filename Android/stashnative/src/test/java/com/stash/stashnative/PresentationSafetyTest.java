package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.animation.ValueAnimator;
import android.view.MotionEvent;
import android.view.View;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebView;
import android.widget.FrameLayout;
import androidx.core.graphics.Insets;
import androidx.core.view.WindowInsetsCompat;
import java.lang.reflect.Field;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.LooperMode;
import org.robolectric.shadows.ShadowLooper;

/** Exercises races between motion, queued bridge events, and renderer loss. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class PresentationSafetyTest {
  private RecordingCheckout activity;

  @Before public void prepare() {
    activity = Robolectric.buildActivity(RecordingCheckout.class).get();
    activity.options = StashPresentationOptions.card(null);
    activity.rootLayout = new FrameLayout(activity);
    activity.rootLayout.setRight(800);
    activity.rootLayout.setBottom(1400);
    activity.backdropView = new View(activity);
    activity.cardContainer = new StashSheetLayout(activity, 16);
    activity.cardContainer.setLayoutParams(new FrameLayout.LayoutParams(1, 1));
    activity.presentation = new StashPresentationController(activity, activity.options);
  }

  @After public void cleanup() {
    activity.presentation.dispose();
    StashCheckoutWebViewSupport.cancelLoadTimers(activity);
    if (activity.webView != null) activity.webView.destroy();
  }

  @Test public void contentReportReplacingEntryAnimationRestoresFullVisibility() throws Exception {
    activity.presentation.environmentChanged();
    Field field = StashPresentationController.class.getDeclaredField("animator");
    field.setAccessible(true);
    ValueAnimator entering = (ValueAnimator) field.get(activity.presentation);
    assertNotNull(entering);
    entering.setCurrentPlayTime(60);
    assertTrue(activity.backdropView.getAlpha() < 1);
    activity.presentation.contentChanged(250, 480);
    assertEquals(1, activity.backdropView.getAlpha(), 0);
    assertEquals(1, activity.cardContainer.getAlpha(), 0);
  }

  @Test public void processingAndCloseQueuedTogetherCannotDismissPendingPurchase() throws Exception {
    StashCheckoutJsInterface bridge = new StashCheckoutJsInterface(activity);
    Thread worker = new Thread(() -> {
      bridge.onPurchaseProcessing();
      bridge.requestCloseFromPage();
    });
    worker.start();
    worker.join();
    ShadowLooper.idleMainLooper();
    assertTrue(activity.isPurchaseProcessing);
    assertEquals(0, activity.dismissCalls);
    bridge.onProcessingCompleted();
    bridge.requestCloseFromPage();
    assertEquals(1, activity.dismissCalls);
  }

  @Test public void pageCloseObeysAllowDismiss() {
    StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
    config.allowDismiss = false;
    activity.options = StashPresentationOptions.card(config);
    new StashCheckoutJsInterface(activity).requestCloseFromPage();
    assertEquals(0, activity.dismissCalls);
    config.allowDismiss = true;
    activity.options = StashPresentationOptions.card(config);
    new StashCheckoutJsInterface(activity).requestCloseFromPage();
    assertEquals(1, activity.dismissCalls);
  }

  @Test public void pinchAndRemainingPointerCannotDragOrDismissSheet() {
    activity.presentation.environmentChanged();
    MotionEvent down = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, 360, 600, 0);
    assertFalse(activity.presentation.interceptTouch(down));
    MotionEvent.PointerProperties[] properties = new MotionEvent.PointerProperties[2];
    MotionEvent.PointerCoords[] coordinates = new MotionEvent.PointerCoords[2];
    for (int index = 0; index < 2; index++) {
      properties[index] = new MotionEvent.PointerProperties();
      properties[index].id = index;
      coordinates[index] = new MotionEvent.PointerCoords();
      coordinates[index].x = 360;
      coordinates[index].y = 450 + index * 300;
    }
    MotionEvent pinch = MotionEvent.obtain(0, 100, MotionEvent.ACTION_MOVE, 2,
        properties, coordinates, 0, 0, 1, 1, 0, 0, 0, 0);
    assertFalse(activity.presentation.interceptTouch(pinch));
    MotionEvent remaining = MotionEvent.obtain(0, 120, MotionEvent.ACTION_MOVE, 360, 400, 0);
    assertFalse(activity.presentation.interceptTouch(remaining));
    assertFalse(activity.presentation.state.expanded);
    assertEquals(0, activity.dismissCalls);
    down.recycle();
    pinch.recycle();
    remaining.recycle();
    MotionEvent nextDown = MotionEvent.obtain(200, 200, MotionEvent.ACTION_DOWN, 360, 600, 0);
    MotionEvent nextMove = MotionEvent.obtain(200, 300, MotionEvent.ACTION_MOVE, 360, 450, 0);
    assertFalse(activity.presentation.interceptTouch(nextDown));
    assertTrue(activity.presentation.interceptTouch(nextMove));
    nextDown.recycle();
    nextMove.recycle();
  }

  @Test public void processingStartingDuringDragRestoresSheetWithoutDismissal() {
    activity.presentation.environmentChanged();
    MotionEvent down = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, 360, 600, 0);
    MotionEvent move = MotionEvent.obtain(0, 100, MotionEvent.ACTION_MOVE, 360, 760, 0);
    activity.presentation.onTouch(activity.cardContainer, down);
    activity.presentation.onTouch(activity.cardContainer, move);
    assertTrue(activity.cardContainer.getTranslationY() > 0);
    new StashCheckoutJsInterface(activity).onPurchaseProcessing();
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
    MotionEvent up = MotionEvent.obtain(0, 200, MotionEvent.ACTION_UP, 360, 760, 0);
    activity.presentation.onTouch(activity.cardContainer, up);
    assertEquals(0, activity.dismissCalls);
    assertFalse(activity.presentation.state.expanded);
    down.recycle();
    move.recycle();
    up.recycle();
  }

  @Test public void overlayHandleLeavesPageTopButtonsTouchable() throws Exception {
    activity.url = "https://example.invalid/checkout";
    StashCheckoutWebViewSupport.addWebView(activity);
    View page = new View(activity);
    activity.cardContainer.addView(page, new FrameLayout.LayoutParams(-1, -1));
    java.lang.reflect.Method addHandle = StashCheckoutActivity.class.getDeclaredMethod("addDragHandle");
    addHandle.setAccessible(true);
    addHandle.invoke(activity);
    activity.presentation.environmentChanged();
    int width = StashWebViewUtils.dpToPx(activity, 480);
    int height = StashWebViewUtils.dpToPx(activity, 560);
    activity.cardContainer.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
        View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
    activity.cardContainer.layout(0, 0, width, height);
    FrameLayout.LayoutParams web = (FrameLayout.LayoutParams) activity.webView.getLayoutParams();
    assertEquals(0, web.topMargin);
    assertEquals(FrameLayout.LayoutParams.MATCH_PARENT, web.height);
    assertEquals(0, page.getTop());
    assertEquals(height, page.getHeight());
    int[] touches = {0};
    page.setOnTouchListener((view, event) -> { touches[0]++; return true; });
    MotionEvent down = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, width - 10, 10, 0);
    MotionEvent up = MotionEvent.obtain(0, 10, MotionEvent.ACTION_UP, width - 10, 10, 0);
    activity.cardContainer.dispatchTouchEvent(down);
    activity.cardContainer.dispatchTouchEvent(up);
    assertEquals(2, touches[0]);
    View handle = activity.cardContainer.getChildAt(activity.cardContainer.getChildCount() - 1);
    assertTrue(handle.isFocusable());
    assertTrue(handle.performClick());
    assertTrue(activity.presentation.state.expanded);
    down.recycle();
    up.recycle();
  }

  @Test public void keyboardExpandsShortCardAndRestoresItsPreviousSelection() throws Exception {
    activity.rootLayout.setRight(390);
    activity.rootLayout.setBottom(760);
    activity.presentation.state.contentHeightPx = 120;
    activity.presentation.state.measuredWidthPx = 390;
    applyKeyboardInsets(0);
    assertEquals(120, activity.cardContainer.getLayoutParams().height);
    applyKeyboardInsets(300);
    assertFalse(activity.presentation.state.expanded);
    assertTrue(activity.presentation.state.effectiveExpanded());
    assertEquals(420, activity.cardContainer.getLayoutParams().height);
    applyKeyboardInsets(0);
    assertFalse(activity.presentation.state.effectiveExpanded());
    assertEquals(120, activity.cardContainer.getLayoutParams().height);
    activity.presentation.state.selectExpanded(true);
    activity.presentation.environmentChanged();
    assertEquals(696, activity.cardContainer.getLayoutParams().height);
    applyKeyboardInsets(300);
    assertEquals(420, activity.cardContainer.getLayoutParams().height);
    applyKeyboardInsets(0);
    assertTrue(activity.presentation.state.effectiveExpanded());
    assertEquals(696, activity.cardContainer.getLayoutParams().height);
  }

  private void applyKeyboardInsets(int bottom) throws Exception {
    java.lang.reflect.Method apply = StashPresentationController.class.getDeclaredMethod(
        "applyInsets", WindowInsetsCompat.class);
    apply.setAccessible(true);
    apply.invoke(activity.presentation, new WindowInsetsCompat.Builder()
        .setInsets(WindowInsetsCompat.Type.systemBars(), Insets.of(0, 24, 0, 24))
        .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, bottom))
        .setVisible(WindowInsetsCompat.Type.ime(), bottom > 0)
        .build());
  }

  @Test public void rendererRecoveryKeepsGrabberAboveReplacementWebView() throws Exception {
    activity.url = "https://example.invalid/checkout";
    StashCheckoutWebViewSupport.addWebView(activity);
    java.lang.reflect.Method addHandle = StashCheckoutActivity.class.getDeclaredMethod("addDragHandle");
    addHandle.setAccessible(true);
    addHandle.invoke(activity);
    View handle = activity.cardContainer.getChildAt(activity.cardContainer.getChildCount() - 1);
    WebView original = activity.webView;
    Shadows.shadowOf(original).getWebViewClient().onRenderProcessGone(original,
        new RenderProcessGoneDetail() {
          @Override public boolean didCrash() { return false; }
          @Override public int rendererPriorityAtExit() { return 0; }
        });
    assertNotNull(activity.webView);
    assertTrue(activity.webView != original);
    assertTrue(activity.cardContainer.indexOfChild(handle)
        > activity.cardContainer.indexOfChild(activity.webView));
    assertEquals(0, activity.networkErrors);
  }

  @Test public void rendererLossDuringProcessingCancelsWithoutReplayingCheckout() {
    activity.url = "https://example.invalid/checkout";
    StashCheckoutWebViewSupport.addWebView(activity);
    WebView original = activity.webView;
    assertNotNull(original);
    activity.isPurchaseProcessing = true;
    Shadows.shadowOf(original).getWebViewClient().onRenderProcessGone(original,
        new RenderProcessGoneDetail() {
          @Override public boolean didCrash() { return false; }
          @Override public int rendererPriorityAtExit() { return 0; }
        });
    assertNull(activity.webView);
    assertEquals(1, activity.networkErrors);
    assertEquals(0, activity.dismissCalls);
  }

  public static class RecordingCheckout extends StashCheckoutActivity {
    int dismissCalls;
    int networkErrors;

    @Override void dismissWithAnimation() { dismissCalls++; }
    @Override void handleNetworkError() { networkErrors++; }
  }
}
