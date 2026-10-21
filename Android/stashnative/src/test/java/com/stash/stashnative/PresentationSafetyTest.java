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
import org.robolectric.util.ReflectionHelpers.ClassParameter;

/** Exercises races between motion, queued bridge events, and renderer loss. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
@LooperMode(LooperMode.Mode.PAUSED)
public class PresentationSafetyTest {
  private RecordingCheckout activity;

  @Before public void prepare() {
    StashNativePlugin.getInstance().resetPresentationState();
    activity = createCheckout();
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
    StashNativePlugin.getInstance().resetPresentationState();
    activity.presentation.dispose();
    StashCheckoutLoadingSupport.cancelLoadTimers(activity);
    StashCheckoutLoadingSupport.cancelLoadingRevealAnimation(activity);
    if (activity.webView != null) activity.webView.destroy();
  }

  private RecordingCheckout createCheckout() {
    StashNativePlugin plugin = StashNativePlugin.getInstance();
    plugin.isCurrentlyPresented = true;
    Intent intent = new Intent().putExtra(StashCheckoutBridge.EXTRA_SESSION_ID,
        plugin.presentationSessionId);
    return Robolectric.buildActivity(RecordingCheckout.class, intent).get();
  }

  /** The current main-frame bridge token, issuing one for checkouts that never loaded. */
  private static String token(StashCardActivity checkout) {
    return checkout.bridgeDocumentToken != null
        ? checkout.bridgeDocumentToken : checkout.issueBridgeDocumentToken();
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
    StashNative.CardConfig config = new StashNative.CardConfig();
    config.allowDismiss = false;
    activity.options = StashPresentationOptions.card(config);
    StashCheckoutJsInterface bridge = new StashCheckoutJsInterface(activity);
    Thread worker = new Thread(() -> {
      bridge.onPurchaseProcessing(token(activity));
      bridge.requestCloseFromPage(token(activity));
    });
    worker.start();
    worker.join();
    ShadowLooper.idleMainLooper();
    assertTrue(activity.isPurchaseProcessing);
    assertEquals(0, activity.dismissCalls);
    bridge.onProcessingCompleted(token(activity));
    bridge.requestCloseFromPage(token(activity));
    assertEquals(1, activity.dismissCalls);
  }

  @Test public void allowDismissBlocksUserDismissalButNotPageClose() {
    StashNative.CardConfig config = new StashNative.CardConfig();
    config.allowDismiss = false;
    activity.options = StashPresentationOptions.card(config);
    activity.requestUserDismiss();
    assertEquals(0, activity.dismissCalls);
    new StashCheckoutJsInterface(activity).requestCloseFromPage(token(activity));
    assertEquals(1, activity.dismissCalls);
    config.allowDismiss = true;
    activity.options = StashPresentationOptions.card(config);
    activity.requestUserDismiss();
    assertEquals(2, activity.dismissCalls);
    new StashCheckoutJsInterface(activity).requestCloseFromPage(token(activity));
    assertEquals(3, activity.dismissCalls);
  }

  @Test public void cancelDeeplinkIgnoresAllowDismissButRespectsProcessing() {
    StashNative.CardConfig config = new StashNative.CardConfig();
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
    StashNative.CardConfig config = new StashNative.CardConfig();
    config.allowDismiss = false;
    for (boolean success : new boolean[] {true, false}) {
      RecordingCheckout checkout = createCheckout();
      checkout.options = StashPresentationOptions.card(config);
      checkout.isPurchaseProcessing = true;
      StashCheckoutJsInterface bridge = new StashCheckoutJsInterface(checkout);
      List<Intent> broadcasts = Shadows.shadowOf(checkout.getApplication()).getBroadcastIntents();
      int previousCount = broadcasts.size();
      for (int attempt = 0; attempt < 2; attempt++) {
        if (success) bridge.onPaymentSuccess(token(checkout), "order-1");
        else bridge.onPaymentFailure(token(checkout));
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
    StashNative.CardConfig config = new StashNative.CardConfig();
    config.allowDismiss = false;
    config.autoClose = false;
    activity.options = StashPresentationOptions.card(config);
    StashCheckoutJsInterface bridge = new StashCheckoutJsInterface(activity);
    activity.isPurchaseProcessing = true;
    bridge.onPaymentFailure(token(activity));
    assertFalse(activity.isPurchaseProcessing);
    bridge.onPaymentSuccess(token(activity), "retry-order");
    assertFalse(activity.callbackSent);
    assertEquals(0, activity.dismissCalls);
    bridge.requestCloseFromPage(token(activity));
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
    new StashCheckoutJsInterface(activity).onPurchaseProcessing(token(activity));
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
    java.lang.reflect.Method addHandle = StashCardActivity.class.getDeclaredMethod("addDragHandle");
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

  @Test public void webEndsAboveNavigationBarAndReceivesNoInsets() throws Exception {
    activity.rootLayout.setRight(390);
    activity.rootLayout.setBottom(900);
    activity.webView = new WebView(activity);
    activity.cardContainer.addView(activity.webView, new FrameLayout.LayoutParams(
        FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
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
      // Android WebView reports env(safe-area-inset-bottom) as 0, so pages cannot pad for the bar.
      assertEquals(Insets.NONE, content.getInsets(WindowInsetsCompat.Type.navigationBars()));
      FrameLayout.LayoutParams web = (FrameLayout.LayoutParams) activity.webView.getLayoutParams();
      assertEquals(keyboard == 0 ? 24 : 0, web.bottomMargin);
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

  @Test
  @Config(shadows = LoadRecordingWebView.class)
  public void initialLoadStartsOnceWhenWebViewEndsAboveNavigationBar() throws Exception {
    LoadRecordingWebView.loads.clear();
    activity.url = "https://example.invalid/checkout";
    activity.rootLayout.addView(activity.cardContainer);
    // As in onCreate, the WebView exists before the first insets resolve the card.
    StashCheckoutWebViewSupport.addWebView(activity);
    String themed = activity.webViewCommittedReloadUrl;
    WebView original = activity.webView;
    layoutWindow(390, 900);
    ShadowLooper.idleMainLooper(20000, java.util.concurrent.TimeUnit.MILLISECONDS);
    assertEquals(0, LoadRecordingWebView.loads.size());
    assertEquals(0, activity.networkErrors);

    applyKeyboardInsets(0);
    layoutWindow(390, 900);
    assertEquals(24, ((FrameLayout.LayoutParams) original.getLayoutParams()).bottomMargin);
    assertEquals(584 - 24, original.getHeight());
    assertEquals(java.util.Collections.singletonList(original + " " + themed),
        LoadRecordingWebView.loads);
    long deadline = activity.networkDeadlineTargetUptime - android.os.SystemClock.uptimeMillis();
    assertTrue(deadline > CardConstants.WEBVIEW_NETWORK_DEADLINE_MS - 1000
        && deadline <= CardConstants.WEBVIEW_NETWORK_DEADLINE_MS);
    layoutWindow(390, 900);
    assertEquals(1, LoadRecordingWebView.loads.size());

    LoadRecordingWebView.loads.clear();
    Shadows.shadowOf(original).getWebViewClient().onRenderProcessGone(original,
        new RenderProcessGoneDetail() {
          @Override public boolean didCrash() { return false; }
          @Override public int rendererPriorityAtExit() { return 0; }
        });
    WebView replacement = activity.webView;
    assertTrue(replacement != original);
    assertEquals(0, LoadRecordingWebView.loads.size());
    layoutWindow(390, 900);
    assertEquals(java.util.Collections.singletonList(replacement + " " + themed),
        LoadRecordingWebView.loads);
    ShadowLooper.idleMainLooper(CardConstants.WEBVIEW_NETWORK_DEADLINE_MS,
        java.util.concurrent.TimeUnit.MILLISECONDS);
    assertEquals(1, activity.networkErrors);
  }

  private void layoutWindow(int width, int height) {
    activity.rootLayout.measure(
        View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
        View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
    activity.rootLayout.layout(0, 0, width, height);
    ShadowLooper.idleMainLooper();
  }

  /** Records each navigation with its WebView, and lays the WebView out like a plain view. */
  @org.robolectric.annotation.Implements(WebView.class)
  public static class LoadRecordingWebView extends org.robolectric.shadows.ShadowWebView {
    static final List<String> loads = new java.util.ArrayList<>();

    @org.robolectric.annotation.Implementation
    @Override
    protected void loadUrl(String url) {
      loads.add(realView + " " + url);
      super.loadUrl(url);
    }

    @org.robolectric.annotation.Implementation
    @SuppressWarnings("deprecation")
    protected boolean setFrame(int left, int top, int right, int bottom) {
      // On devices the WebView provider applies the frame; Robolectric's provider ignores it.
      return org.robolectric.shadow.api.Shadow.directlyOn(realView, View.class, "setFrame",
          ClassParameter.from(int.class, left), ClassParameter.from(int.class, top),
          ClassParameter.from(int.class, right), ClassParameter.from(int.class, bottom));
    }
  }

  @Test public void rendererRecoveryKeepsGrabberAboveReplacementWebView() throws Exception {
    activity.url = "https://example.invalid/checkout";
    StashCheckoutWebViewSupport.addWebView(activity);
    java.lang.reflect.Method addHandle = StashCardActivity.class.getDeclaredMethod("addDragHandle");
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

  private Object controllerField(String name) throws Exception {
    Field field = StashPresentationController.class.getDeclaredField(name);
    field.setAccessible(true);
    return field.get(activity.presentation);
  }

  /** A floating card on an 800 x 1400 window, with its entrance finished. */
  private StashCheckoutSizing.Box presentFloatingCard() throws Exception {
    activity.presentation.environmentChanged();
    ValueAnimator entering = currentAnimation();
    if (entering != null) entering.end();
    assertFalse(((StashCheckoutSizing.Layout) controllerField("layout")).bottomAttached);
    return (StashCheckoutSizing.Box) controllerField("shownFrame");
  }

  @Test public void floatingHandleDragNeitherExpandsNorResizesTheCard() throws Exception {
    StashCheckoutSizing.Box resting = presentFloatingCard();
    View handle = new View(activity);
    MotionEvent down = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, 400, 600, 0);
    MotionEvent move = MotionEvent.obtain(0, 100, MotionEvent.ACTION_MOVE, 400, 200, 0);
    MotionEvent up = MotionEvent.obtain(0, 200, MotionEvent.ACTION_UP, 400, 200, 0);
    activity.presentation.onTouch(handle, down);
    activity.presentation.onTouch(handle, move);
    StashCheckoutSizing.Box dragged = (StashCheckoutSizing.Box) controllerField("shownFrame");
    assertEquals(resting.top, dragged.top);
    assertEquals(resting.bottom, dragged.bottom);
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
    activity.presentation.onTouch(handle, up);
    assertFalse(activity.presentation.state.expanded);
    assertEquals(0, activity.dismissCalls);
    down.recycle();
    move.recycle();
    up.recycle();
  }

  @Test public void draggedFloatingCardSlidesOffScreenWhenDismissed() throws Exception {
    StashCheckoutSizing.Box frame = presentFloatingCard();
    View handle = new View(activity);
    MotionEvent down = MotionEvent.obtain(0, 0, MotionEvent.ACTION_DOWN, 400, 600, 0);
    MotionEvent move = MotionEvent.obtain(0, 100, MotionEvent.ACTION_MOVE, 400, 760, 0);
    activity.presentation.onTouch(handle, down);
    activity.presentation.onTouch(handle, move);
    float dragged = activity.cardContainer.getTranslationY();
    assertTrue(dragged > 0);
    activity.isDismissing = true;
    activity.presentation.dismiss(null);
    // The card continues from the finger instead of snapping back to rest.
    assertEquals(dragged, activity.cardContainer.getTranslationY(), 0);
    ValueAnimator dismissing = currentAnimation();
    dismissing.setCurrentPlayTime(60);
    assertTrue(activity.cardContainer.getTranslationY() > dragged);
    assertEquals(1, activity.cardContainer.getAlpha(), 0);
    dismissing.end();
    assertTrue(activity.cardContainer.getTranslationY() >= 1400 - frame.top);
    assertEquals(0, activity.backdropView.getAlpha(), 0);
    down.recycle();
    move.recycle();
  }

  @Test public void undraggedFloatingCardFadesInPlaceWhenDismissed() throws Exception {
    presentFloatingCard();
    activity.isDismissing = true;
    activity.presentation.dismiss(null);
    ValueAnimator dismissing = currentAnimation();
    dismissing.setCurrentPlayTime(60);
    assertTrue(activity.cardContainer.getAlpha() < 1);
    dismissing.end();
    assertEquals(0, activity.cardContainer.getTranslationY(), 0);
    assertEquals(0, activity.cardContainer.getAlpha(), 0);
  }

  public static class RecordingCheckout extends StashCardActivity {
    int dismissCalls;
    int networkErrors;

    @Override void dismissWithAnimation() { dismissCalls++; }
    @Override void handleNetworkError() { networkErrors++; }
  }
}
