package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.animation.ValueAnimator;
import android.content.Intent;
import android.view.MotionEvent;
import android.view.View;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebView;
import android.widget.FrameLayout;
import androidx.core.graphics.Insets;
import androidx.core.view.WindowInsetsCompat;
import java.lang.reflect.Field;
import java.util.List;
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
    activity.backdropView = new View(activity);
    activity.cardContainer = new StashSheetLayout(activity, 16);
    activity.cardContainer.setLayoutParams(new FrameLayout.LayoutParams(1, 1));
    activity.presentation = new StashPresentationController(activity, activity.options);
    activity.onEnterAnimationComplete();
    activity.rootLayout.setRight(800);
    activity.rootLayout.setBottom(1400);
  }

  @After public void cleanup() {
    activity.presentation.dispose();
    StashCheckoutLoadingSupport.cancelLoadTimers(activity);
    StashCheckoutLoadingSupport.cancelLoadingRevealAnimation(activity);
    if (activity.webView != null) activity.webView.destroy();
  }

  @Test public void cancelledLoadingFadeCannotRevealContentFromAnAbandonedLoad() {
    activity.webView = new WebView(activity);
    activity.loadingView = new View(activity);
    activity.cardContainer.addView(activity.webView);
    activity.cardContainer.addView(activity.loadingView);
    StashCheckoutLoadingSupport.revealWebViewAndRemoveLoading(activity);
    android.animation.Animator fade = activity.webViewRevealAnimator;
    assertNotNull(fade);
    assertTrue(fade.isStarted());
    StashCheckoutLoadingSupport.cancelLoadingRevealAnimation(activity);
    assertFalse(fade.isStarted());
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1));
    assertEquals(0, activity.webView.getAlpha(), 0);
    assertEquals(1, activity.loadingView.getAlpha(), 0);
    assertFalse(activity.webViewLoadingRevealComplete);
    assertFalse(activity.pageLoadedCallbackSent);
  }

  @Test public void contentReportPreservesEntryAnimation() throws Exception {
    activity.presentation.environmentChanged();
    ValueAnimator entering = currentAnimation();
    assertNotNull(entering);
    entering.setCurrentPlayTime(60);
    float opacity = activity.backdropView.getAlpha();
    assertTrue(opacity > 0 && opacity < 1);
    activity.presentation.contentChanged(250, 480);
    assertTrue(entering.isStarted());
    assertEquals(opacity, activity.backdropView.getAlpha(), 0);
    assertEquals(opacity, activity.cardContainer.getAlpha(), 0);
    entering.end();
    assertEquals(1, activity.backdropView.getAlpha(), 0);
    assertEquals(1, activity.cardContainer.getAlpha(), 0);
  }

  @Test @Config(sdk = {21, 28})
  public void entranceWaitsForWindowTransitionAndStartsOnlyOnce() throws Exception {
    activity.presentation.dispose();
    activity.presentation = new StashPresentationController(activity, activity.options);
    activity.rootLayout.setRight(390);
    activity.presentation.environmentChanged();
    activity.presentation.contentChanged(250, 390);
    assertNull(currentAnimation());
    assertEquals(0, activity.backdropView.getAlpha(), 0);
    assertEquals(activity.cardContainer.getLayoutParams().height,
        activity.cardContainer.getTranslationY(), 0);
    activity.onEnterAnimationComplete();
    ValueAnimator entering = currentAnimation();
    assertNotNull(entering);
    entering.setCurrentPlayTime(60);
    float translation = activity.cardContainer.getTranslationY();
    activity.onEnterAnimationComplete();
    assertTrue(entering.isStarted());
    assertEquals(translation, activity.cardContainer.getTranslationY(), 0);
    entering.end();
    activity.onEnterAnimationComplete();
    assertNull(currentAnimation());
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
  }

  @Test @Config(sdk = {21, 28})
  public void lateWindowTransitionCannotPresentADismissedCard() throws Exception {
    activity.presentation.dispose();
    activity.presentation = new StashPresentationController(activity, activity.options);
    activity.rootLayout.setRight(390);
    activity.presentation.environmentChanged();
    activity.isDismissing = true;
    int[] completed = {0};
    activity.presentation.dismiss(() -> completed[0]++);
    ValueAnimator dismissing = currentAnimation();
    activity.onEnterAnimationComplete();
    assertTrue(dismissing.isStarted());
    assertEquals(0, activity.backdropView.getAlpha(), 0);
    dismissing.end();
    activity.onEnterAnimationComplete();
    assertNull(currentAnimation());
    assertEquals(1, completed[0]);
  }

  @Test public void repeatedLayoutAndInsetsUpdatesDoNotCancelSlideIn() throws Exception {
    activity.rootLayout.setRight(390);
    activity.presentation.environmentChanged();
    ValueAnimator entering = currentAnimation();
    entering.setCurrentPlayTime(60);
    float opacity = activity.backdropView.getAlpha();
    float translation = activity.cardContainer.getTranslationY();
    assertTrue(translation > 0);
    activity.presentation.environmentChanged();
    assertEquals(translation, activity.cardContainer.getTranslationY(), 0);
    assertEquals(opacity, activity.backdropView.getAlpha(), 0);
    applyKeyboardInsets(0);
    assertTrue(entering.isStarted());
    assertEquals(opacity, activity.backdropView.getAlpha(), 0);
    assertEquals(activity.cardContainer.getLayoutParams().height * (1 - opacity),
        activity.cardContainer.getTranslationY(), 0.01f);
    entering.end();
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
    activity.presentation.environmentChanged();
    assertNull(currentAnimation());
  }

  @Test public void windowResizeDuringEntryKeepsProgressAndUsesNewBounds() throws Exception {
    activity.rootLayout.setRight(390);
    activity.presentation.environmentChanged();
    ValueAnimator entering = currentAnimation();
    entering.setCurrentPlayTime(60);
    float opacity = activity.backdropView.getAlpha();
    activity.rootLayout.setBottom(400);
    activity.presentation.environmentChanged();
    FrameLayout.LayoutParams frame =
        (FrameLayout.LayoutParams) activity.cardContainer.getLayoutParams();
    assertEquals(400, frame.topMargin + frame.height);
    assertEquals(frame.height * (1 - opacity), activity.cardContainer.getTranslationY(), 0.01f);
    entering.setCurrentPlayTime(120);
    assertEquals(frame.height * (1 - activity.backdropView.getAlpha()),
        activity.cardContainer.getTranslationY(), 0.01f);
    activity.rootLayout.setRight(800);
    activity.presentation.environmentChanged();
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
    assertEquals(activity.backdropView.getAlpha(), activity.cardContainer.getAlpha(), 0);
    assertTrue(entering.isStarted());
    entering.end();
    assertEquals(1, activity.cardContainer.getAlpha(), 0);
  }

  @Test public void dismissalDuringEntryKeepsPositionAndOpacityAndCompletesOnce() throws Exception {
    activity.rootLayout.setRight(390);
    activity.presentation.environmentChanged();
    ValueAnimator entering = currentAnimation();
    entering.setCurrentPlayTime(60);
    float translation = activity.cardContainer.getTranslationY();
    float opacity = activity.backdropView.getAlpha();
    activity.isDismissing = true;
    int[] completed = {0};
    activity.presentation.dismiss(() -> completed[0]++);
    assertFalse(entering.isStarted());
    assertEquals(translation, activity.cardContainer.getTranslationY(), 0);
    assertEquals(opacity, activity.backdropView.getAlpha(), 0);
    activity.presentation.environmentChanged();
    ValueAnimator dismissing = currentAnimation();
    dismissing.setCurrentPlayTime(60);
    assertTrue(activity.cardContainer.getTranslationY() > translation);
    assertTrue(activity.backdropView.getAlpha() < opacity);
    dismissing.end();
    assertEquals(1, completed[0]);
    assertEquals(0, activity.backdropView.getAlpha(), 0);
    activity.presentation.dispose();
    assertEquals(1, completed[0]);
  }

  private ValueAnimator currentAnimation() throws Exception {
    Field field = StashPresentationController.class.getDeclaredField("animator");
    field.setAccessible(true);
    return (ValueAnimator) field.get(activity.presentation);
  }

  @Test public void processingAndCloseQueuedTogetherCannotDismissPendingPurchase() throws Exception {
    StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
    config.allowDismiss = false;
    activity.options = StashPresentationOptions.card(config);
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

  @Test public void allowDismissBlocksUserDismissalButNotPageClose() {
    StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
    config.allowDismiss = false;
    activity.options = StashPresentationOptions.card(config);
    activity.requestUserDismiss();
    assertEquals(0, activity.dismissCalls);
    new StashCheckoutJsInterface(activity).requestCloseFromPage();
    assertEquals(1, activity.dismissCalls);
    config.allowDismiss = true;
    activity.options = StashPresentationOptions.card(config);
    activity.requestUserDismiss();
    assertEquals(2, activity.dismissCalls);
    new StashCheckoutJsInterface(activity).requestCloseFromPage();
    assertEquals(3, activity.dismissCalls);
  }

  @Test public void cancelDeeplinkIgnoresAllowDismissButRespectsProcessing() {
    StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
    config.allowDismiss = false;
    activity.options = StashPresentationOptions.card(config);
    activity.isPurchaseProcessing = true;
    assertTrue(StashCheckoutNavigationSupport.handleDeeplinkNavigation(
        activity, "testapp://stash-pay/cancel"));
    assertEquals(0, activity.dismissCalls);
    activity.isPurchaseProcessing = false;
    assertTrue(StashCheckoutNavigationSupport.handleDeeplinkNavigation(
        activity, "testapp://stash-pay/cancel"));
    assertEquals(1, activity.dismissCalls);
  }

  @Test public void paymentResultsIgnoreAllowDismissAndAutoCloseOnce() {
    StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
    config.allowDismiss = false;
    for (boolean success : new boolean[] {true, false}) {
      RecordingCheckout checkout = Robolectric.buildActivity(RecordingCheckout.class).get();
      checkout.options = StashPresentationOptions.card(config);
      checkout.isPurchaseProcessing = true;
      StashCheckoutJsInterface bridge = new StashCheckoutJsInterface(checkout);
      List<Intent> broadcasts = Shadows.shadowOf(checkout.getApplication()).getBroadcastIntents();
      int previousCount = broadcasts.size();
      for (int attempt = 0; attempt < 2; attempt++) {
        if (success) bridge.onPaymentSuccess("order-1");
        else bridge.onPaymentFailure();
      }
      broadcasts = Shadows.shadowOf(checkout.getApplication()).getBroadcastIntents();
      assertEquals(previousCount + 1, broadcasts.size());
      Intent event = broadcasts.get(previousCount);
      assertEquals(success ? CardConstants.BROADCAST_CHECKOUT_PAYMENT_SUCCESS
          : CardConstants.BROADCAST_CHECKOUT_PAYMENT_FAILURE, event.getAction());
      assertEquals(success ? "order-1" : null,
          event.getStringExtra(CardConstants.BROADCAST_EXTRA_PAYMENT_ORDER));
      assertTrue(event.getBooleanExtra(CardConstants.BROADCAST_EXTRA_WILL_CLOSE, false));
      assertFalse(checkout.isPurchaseProcessing);
      assertTrue(checkout.callbackSent);
      assertEquals(1, checkout.dismissCalls);
    }
  }

  @Test public void paymentRetryWithAutoCloseDisabledCanStillCloseFromPage() {
    StashNativeCard.CardConfig config = new StashNativeCard.CardConfig();
    config.allowDismiss = false;
    config.autoClose = false;
    activity.options = StashPresentationOptions.card(config);
    StashCheckoutJsInterface bridge = new StashCheckoutJsInterface(activity);
    activity.isPurchaseProcessing = true;
    bridge.onPaymentFailure();
    assertFalse(activity.isPurchaseProcessing);
    bridge.onPaymentSuccess("retry-order");
    assertFalse(activity.callbackSent);
    assertEquals(0, activity.dismissCalls);
    bridge.requestCloseFromPage();
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
    prepareContentDrag();
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

  @Test public void upwardContentDragCanReturnToRestingWithoutDismissing() throws Exception {
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
    assertFalse(activity.presentation.state.expanded);
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
    assertEquals(0, activity.dismissCalls);
    down.recycle();
    upMove.recycle();
    reversal.recycle();
    up.recycle();
  }

  @Test public void contentExpansionFollowsFingerAndSmallPullReturnsToResting() {
    prepareContentDrag();
    int resting = activity.cardContainer.getLayoutParams().height;
    contentTouch(MotionEvent.ACTION_DOWN, 600, 0);
    contentTouch(MotionEvent.ACTION_MOVE, 565, 200);
    assertEquals(resting + 35, activity.cardContainer.getLayoutParams().height);
    assertFalse(activity.presentation.state.expanded);
    contentTouch(MotionEvent.ACTION_MOVE, 550, 400);
    assertEquals(resting + 50, activity.cardContainer.getLayoutParams().height);
    assertFalse(activity.presentation.state.expanded);
    contentTouch(MotionEvent.ACTION_UP, 550, 1400);
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1));
    assertEquals(resting, activity.cardContainer.getLayoutParams().height);
    assertFalse(activity.presentation.state.expanded);
    assertEquals(0, activity.dismissCalls);
  }

  @Test public void longContentPullSettlesExpandedOnlyAfterRelease() {
    prepareContentDrag();
    int resting = activity.cardContainer.getLayoutParams().height;
    contentTouch(MotionEvent.ACTION_DOWN, 600, 0);
    contentTouch(MotionEvent.ACTION_MOVE, 500, 500);
    assertEquals(resting + 100, activity.cardContainer.getLayoutParams().height);
    assertFalse(activity.presentation.state.expanded);
    contentTouch(MotionEvent.ACTION_UP, 500, 1500);
    assertTrue(activity.presentation.state.expanded);
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1));
    assertEquals(720, activity.cardContainer.getLayoutParams().height);
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
  }

  @Test public void contentOverdragStaysCappedAndCancellationRestoresSelection() {
    prepareContentDrag();
    int resting = activity.cardContainer.getLayoutParams().height;
    contentTouch(MotionEvent.ACTION_DOWN, 600, 0);
    contentTouch(MotionEvent.ACTION_MOVE, 100, 500);
    assertEquals(720, activity.cardContainer.getLayoutParams().height);
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
    assertFalse(activity.presentation.state.expanded);
    contentTouch(MotionEvent.ACTION_CANCEL, 100, 600);
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1));
    assertEquals(resting, activity.cardContainer.getLayoutParams().height);
    assertFalse(activity.presentation.state.expanded);
    assertEquals(0, activity.dismissCalls);
  }

  @Test public void programmaticSelectionInterruptsContentDrag() {
    prepareContentDrag();
    contentTouch(MotionEvent.ACTION_DOWN, 600, 0);
    contentTouch(MotionEvent.ACTION_MOVE, 565, 200);
    activity.presentation.setExpanded(true);
    contentTouch(MotionEvent.ACTION_MOVE, 750, 400);
    contentTouch(MotionEvent.ACTION_UP, 750, 500);
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1));
    assertTrue(activity.presentation.state.expanded);
    assertEquals(720, activity.cardContainer.getLayoutParams().height);
    assertEquals(0, activity.dismissCalls);
  }

  private void prepareContentDrag() {
    activity.rootLayout.setRight(390);
    activity.presentation.environmentChanged();
    Shadows.shadowOf(android.os.Looper.getMainLooper()).idleFor(java.time.Duration.ofSeconds(1));
  }

  private void contentTouch(int action, float y, long time) {
    MotionEvent event = MotionEvent.obtain(0, time, action, 180, y, 0);
    if (activity.presentation.interceptTouch(event)) {
      activity.presentation.onTouch(activity.cardContainer, event);
    }
    event.recycle();
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
