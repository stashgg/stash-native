package com.stash.stashnative;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;

import android.webkit.ValueCallback;
import android.webkit.WebView;
import java.lang.reflect.Field;
import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

/** Validates document and viewport races without relying on a stubbed JavaScript engine. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class ContentSizeTest {
  private StashCheckoutActivity activity;
  private TestWebView web;
  private StashContentSizeSupport support;
  private String token;

  @Before
  public void prepare() throws Exception {
    activity = Robolectric.buildActivity(StashCheckoutActivity.class).get();
    activity.presentation =
        new StashPresentationController(activity, StashPresentationOptions.card(null));
    web = new TestWebView(activity);
    web.setRight(780);
    web.setBottom(900);
    activity.webView = web;
    support = new StashContentSizeSupport(activity);
    commit();
    assertNotNull(token);
    assertEquals(780, web.getWidth());
  }

  private void commit() throws Exception {
    support.navigationStarted(web.getUrl());
    support.documentCommitted(web, web.getUrl());
    Field field = StashContentSizeSupport.class.getDeclaredField("documentId");
    field.setAccessible(true);
    token = (String) field.get(support);
    web.pending = null;
  }

  private String report(Object height, Object width, Object scale, String document)
      throws Exception {
    return new JSONObject()
        .put("height", height)
        .put("viewportWidth", width)
        .put("scale", scale)
        .put("documentId", document)
        .toString();
  }

  private void reply(double width, double scale, String document) throws Exception {
    ValueCallback<String> callback = web.pending;
    web.pending = null;
    assertNotNull(callback);
    callback.onReceiveValue(new JSONArray().put(width).put(scale).put(document).toString());
  }

  @Test
  public void convertsCssHeightUsingCurrentNativeViewport() throws Exception {
    support.accept(report(240, 390, 1, token));
    reply(390, 1, token);
    assertEquals(480, activity.presentation.state.contentForWidth(780), 0.01);
  }

  @Test public void largeFiniteHintIsAcceptedForGeometryToClamp() throws Exception {
    support.accept(report(1e12, 390, 1, token));
    reply(390, 1, token);
    assertEquals(2e12, activity.presentation.state.contentHeightPx, 0.01);
  }

  @Test
  public void rejectsWrongTypesInvalidNumbersScaleAndDocument() throws Exception {
    for (Object height : new Object[] {"240", true, -10, 0, JSONObject.NULL}) {
      support.accept(report(height, 390, 1, token));
      assertNull(web.pending);
    }
    support.accept(report(240, "390", 1, token));
    assertNull(web.pending);
    support.accept(report(240, 390, 2, token));
    assertNull(web.pending);
    support.accept(report(240, 390, 1, "old-document"));
    assertNull(web.pending);
    assertEquals(0, activity.presentation.state.contentHeightPx, 0);
  }

  @Test
  public void rejectsCurrentCssViewportMismatch() throws Exception {
    support.accept(report(240, 390, 1, token));
    reply(500, 1, token);
    assertEquals(0, activity.presentation.state.contentHeightPx, 0);
    support.accept(report(240, 390, 1, token));
    reply(390, 1.2, token);
    assertEquals(0, activity.presentation.state.contentHeightPx, 0);
  }

  @Test
  public void rejectsNativeResizeWhileJavaScriptValidationIsPending() throws Exception {
    support.accept(report(240, 390, 1, token));
    web.setRight(900);
    reply(390, 1, token);
    assertEquals(0, activity.presentation.state.contentHeightPx, 0);
  }

  @Test
  public void rejectsNavigationAndDisposalWhileValidationIsPending() throws Exception {
    support.accept(report(240, 390, 1, token));
    support.navigationStarted("https://example.invalid/next");
    reply(390, 1, token);
    assertEquals(0, activity.presentation.state.contentHeightPx, 0);
    commit();
    support.accept(report(240, 390, 1, token));
    support.dispose();
    reply(390, 1, token);
    assertEquals(0, activity.presentation.state.contentHeightPx, 0);
  }

  @Test
  public void oldValidationCannotReplaceNewerReport() throws Exception {
    support.accept(report(240, 390, 1, token));
    ValueCallback<String> first = web.pending;
    support.accept(report(300, 390, 1, token));
    reply(390, 1, token);
    first.onReceiveValue(new JSONArray().put(390).put(1).put(token).toString());
    assertEquals(600, activity.presentation.state.contentHeightPx, 0.01);
  }

  @Test
  public void validResetRestoresFallbackButStaleResetCannotClearNewHeight() throws Exception {
    support.accept(report(240, 390, 1, token));
    reply(390, 1, token);
    String reset =
        new JSONObject()
            .put("reset", true)
            .put("viewportWidth", 390)
            .put("scale", 1)
            .put("documentId", token)
            .toString();
    support.accept(reset);
    ValueCallback<String> staleReset = web.pending;
    support.accept(report(300, 390, 1, token));
    reply(390, 1, token);
    staleReset.onReceiveValue(new JSONArray().put(390).put(1).put(token).toString());
    assertEquals(600, activity.presentation.state.contentHeightPx, 0);
    support.accept(reset);
    reply(390, 1, token);
    assertEquals(0, activity.presentation.state.contentHeightPx, 0);
  }

  private static final class TestWebView extends WebView {
    ValueCallback<String> pending;

    TestWebView(StashCheckoutActivity context) {
      super(context);
    }

    @Override
    public String getUrl() {
      return "https://example.invalid/checkout";
    }

    @Override
    public void evaluateJavascript(String script, ValueCallback<String> callback) {
      if (callback != null) pending = callback;
    }
  }
}
