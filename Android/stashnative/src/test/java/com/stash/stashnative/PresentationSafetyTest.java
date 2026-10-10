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
    StashCheckoutWebViewSupport.cancelLoadingRevealAnimation(activity);
    if (activity.webView != null) activity.webView.destroy();
  }

  @Test public void cancelledLoadingFadeCannotRevealContentFromAnAbandonedLoad() {
    activity.webView = new WebView(activity);
    activity.loadingView = new View(activity);
    activity.cardContainer.addView(activity.webView);
    activity.cardContainer.addView(activity.loadingView);
    StashCheckoutWebViewSupport.revealWebViewAndRemoveLoading(activity);
    android.animation.Animator fade = activity.webViewRevealAnimator;
    assertNotNull(fade);
    assertTrue(fade.isStarted());
    StashCheckoutWebViewSupport.cancelLoadingRevealAnimation(activity);
    assertFalse(fade.isStarted());
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1));
    assertEquals(0, activity.webView.getAlpha(), 0);
    assertEquals(1, activity.loadingView.getAlpha(), 0);
    assertFalse(activity.webViewLoadingRevealComplete);
    assertFalse(activity.pageLoadedCallbackSent);
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
    activity.rootLayout.setRight(390);
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
    View handle = new View(activity);
    activity.presentation.onTouch(handle, down);
    activity.presentation.onTouch(handle, move);
    assertTrue(activity.cardContainer.getTranslationY() > 0);
    new StashCheckoutJsInterface(activity).onPurchaseProcessing();
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
    MotionEvent up = MotionEvent.obtain(0, 200, MotionEvent.ACTION_UP, 360, 760, 0);
    activity.presentation.onTouch(handle, up);
    assertEquals(0, activity.dismissCalls);
    assertFalse(activity.presentation.state.expanded);
    down.recycle();
    move.recycle();
    up.recycle();
  }

  @Test public void downwardContentSwipeNeverMovesCollapsedOrExpandedCard() {
    activity.rootLayout.setRight(390);
    activity.presentation.environmentChanged();
    for (boolean expanded : new boolean[] {false, true}) {
      activity.presentation.state.selectExpanded(expanded);
      activity.presentation.environmentChanged();
      final int height = activity.cardContainer.getLayoutParams().height;
      MotionEvent down = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, 180, 600, 0);
      MotionEvent move = MotionEvent.obtain(0, 100, MotionEvent.ACTION_MOVE, 180, 900, 0);
      MotionEvent up = MotionEvent.obtain(0, 200, MotionEvent.ACTION_UP, 180, 900, 0);
      assertFalse(activity.presentation.interceptTouch(down));
      assertFalse(activity.presentation.interceptTouch(move));
      assertFalse(activity.presentation.interceptTouch(up));
      assertEquals(height, activity.cardContainer.getLayoutParams().height);
      assertEquals(0, activity.cardContainer.getTranslationY(), 0);
      assertEquals(expanded, activity.presentation.state.expanded);
      assertEquals(0, activity.dismissCalls);
      down.recycle();
      move.recycle();
      up.recycle();
    }
  }

  @Test public void upwardContentExpansionCannotReverseIntoCollapseOrDismissal() throws Exception {
    activity.rootLayout.setRight(390);
    activity.presentation.environmentChanged();
    Field animation = StashPresentationController.class.getDeclaredField("animator");
    animation.setAccessible(true);
    ((ValueAnimator) animation.get(activity.presentation)).end();
    MotionEvent down = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, 180, 600, 0);
    MotionEvent upMove = MotionEvent.obtain(0, 100, MotionEvent.ACTION_MOVE, 180, 450, 0);
    final MotionEvent reversal = MotionEvent.obtain(0, 200, MotionEvent.ACTION_MOVE, 180, 950, 0);
    final MotionEvent up = MotionEvent.obtain(0, 300, MotionEvent.ACTION_UP, 180, 950, 0);
    assertFalse(activity.presentation.interceptTouch(down));
    assertTrue(activity.presentation.interceptTouch(upMove));
    activity.presentation.onTouch(activity.cardContainer, upMove);
    activity.presentation.onTouch(activity.cardContainer, reversal);
    activity.presentation.onTouch(activity.cardContainer, up);
    assertTrue(activity.presentation.state.expanded);
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
    assertEquals(0, activity.dismissCalls);
    down.recycle();
    upMove.recycle();
    reversal.recycle();
    up.recycle();
  }

  @Test public void resizingWindowCancelsHandleDragBeforeItsOldCoordinatesCanDismiss() {
    activity.presentation.environmentChanged();
    View handle = new View(activity);
    MotionEvent down = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, 360, 600, 0);
    MotionEvent move = MotionEvent.obtain(0, 100, MotionEvent.ACTION_MOVE, 360, 760, 0);
    activity.presentation.onTouch(handle, down);
    activity.presentation.onTouch(handle, move);
    activity.rootLayout.setBottom(700);
    activity.presentation.environmentChanged();
    MotionEvent up = MotionEvent.obtain(0, 200, MotionEvent.ACTION_UP, 360, 960, 0);
    activity.presentation.onTouch(handle, up);
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
    assertEquals(0, activity.dismissCalls);
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
    assertEquals(144, activity.cardContainer.getLayoutParams().height);
    applyKeyboardInsets(300);
    assertFalse(activity.presentation.state.expanded);
    assertTrue(activity.presentation.state.effectiveExpanded());
    assertEquals(420, activity.cardContainer.getLayoutParams().height);
    applyKeyboardInsets(0);
    assertFalse(activity.presentation.state.effectiveExpanded());
    assertEquals(144, activity.cardContainer.getLayoutParams().height);
    activity.presentation.state.selectExpanded(true);
    activity.presentation.environmentChanged();
    assertEquals(720, activity.cardContainer.getLayoutParams().height);
    applyKeyboardInsets(300);
    assertEquals(420, activity.cardContainer.getLayoutParams().height);
    applyKeyboardInsets(0);
    assertTrue(activity.presentation.state.effectiveExpanded());
    assertEquals(720, activity.cardContainer.getLayoutParams().height);
  }

  @Test public void attachedCardPaintsToWindowBottomInBothStates() throws Exception {
    activity.rootLayout.setRight(390);
    activity.rootLayout.setBottom(900);
    for (boolean expanded : new boolean[] {false, true}) {
      activity.presentation.state.selectExpanded(expanded);
      applyKeyboardInsets(0);
      activity.presentation.environmentChanged();
      FrameLayout.LayoutParams frame =
          (FrameLayout.LayoutParams) activity.cardContainer.getLayoutParams();
      assertEquals(900, frame.topMargin + frame.height);
      assertEquals((expanded ? 720 : 560) + 24, frame.height);
    }
  }

  @Test public void keyboardOwnsBottomEdgeAndClosingItRestoresPaintThrough() throws Exception {
    activity.rootLayout.setRight(390);
    activity.rootLayout.setBottom(900);
    for (int keyboard : new int[] {0, 12, 24, 300, 24, 12, 0}) {
      applyKeyboardInsets(keyboard);
      FrameLayout.LayoutParams frame =
          (FrameLayout.LayoutParams) activity.cardContainer.getLayoutParams();
      assertEquals(900 - keyboard, frame.topMargin + frame.height);
    }
  }

  @Test public void floatingCardDoesNotExtendThroughNavigationBar() throws Exception {
    activity.rootLayout.setRight(800);
    activity.rootLayout.setBottom(900);
    applyKeyboardInsets(0);
    FrameLayout.LayoutParams frame =
        (FrameLayout.LayoutParams) activity.cardContainer.getLayoutParams();
    assertEquals(560, frame.height);
    assertEquals(900, frame.topMargin * 2 + frame.height);
  }

  @Test public void upperFoldPaneCannotExtendAcrossSeparatingHinge() throws Exception {
    activity.rootLayout.setRight(390);
    activity.rootLayout.setBottom(900);
    Field hinge = StashPresentationController.class.getDeclaredField("hinge");
    hinge.setAccessible(true);
    hinge.set(activity.presentation, new StashCheckoutSizing.Box(0, 550, 390, 570));
    applyKeyboardInsets(0);
    FrameLayout.LayoutParams frame =
        (FrameLayout.LayoutParams) activity.cardContainer.getLayoutParams();
    assertEquals(550, frame.topMargin + frame.height);
    hinge.set(activity.presentation, new StashCheckoutSizing.Box(0, 300, 390, 320));
    activity.presentation.environmentChanged();
    frame = (FrameLayout.LayoutParams) activity.cardContainer.getLayoutParams();
    assertEquals(900, frame.topMargin + frame.height);
    assertTrue(frame.topMargin > 320);
  }

  @Test public void webReceivesOnlyInsetsNotAlreadyHandledByNativeBounds() throws Exception {
    activity.rootLayout.setRight(390);
    activity.rootLayout.setBottom(900);
    java.lang.reflect.Method contentInsets = StashPresentationController.class.getDeclaredMethod(
        "contentInsets", WindowInsetsCompat.class);
    contentInsets.setAccessible(true);
    for (int keyboard : new int[] {0, 300, 0}) {
      applyKeyboardInsets(keyboard);
      WindowInsetsCompat supplied = new WindowInsetsCompat.Builder()
          .setInsets(WindowInsetsCompat.Type.systemBars(), Insets.of(0, 24, 0, 24))
          .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, keyboard))
          .build();
      WindowInsetsCompat content =
          (WindowInsetsCompat) contentInsets.invoke(activity.presentation, supplied);
      assertEquals(Insets.NONE, content.getInsets(WindowInsetsCompat.Type.ime()));
      assertEquals(Insets.NONE, content.getInsets(WindowInsetsCompat.Type.statusBars()));
      assertEquals(Insets.of(0, 0, 0, keyboard == 0 ? 24 : 0),
          content.getInsets(WindowInsetsCompat.Type.navigationBars()));
    }
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
