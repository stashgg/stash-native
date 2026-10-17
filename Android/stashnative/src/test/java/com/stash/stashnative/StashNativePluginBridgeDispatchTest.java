package com.stash.stashnative;

import static org.junit.Assert.*;

import android.content.Intent;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class StashNativePluginBridgeDispatchTest {

  private StashNativePlugin plugin;
  private StashNative.StashNativeListener previousListener;
  private boolean previousIsCurrentlyPresented;

  @Before
  public void setUp() throws Exception {
    plugin = StashNativePlugin.getInstance();
    previousListener = getListenerField(plugin);
    previousIsCurrentlyPresented = plugin.isCurrentlyPresented();
    setIsCurrentlyPresented(plugin, true);
  }

  @After
  public void tearDown() throws Exception {
    plugin.setListener(previousListener);
    setIsCurrentlyPresented(plugin, previousIsCurrentlyPresented);
  }

  @Test
  public void dispatchPageLoaded_forwardsLoadTimeToListener() throws Exception {
    final long[] capturedMs = new long[1];
    final boolean[] called = new boolean[1];
    plugin.setListener(
        new StashNative.StashNativeListenerAdapter() {
          @Override
          public void onPageLoaded(long loadTimeMs) {
            called[0] = true;
            capturedMs[0] = loadTimeMs;
          }
        });

    Intent intent = new Intent(CardConstants.BROADCAST_CHECKOUT_PAGE_LOADED);
    intent.putExtra(CardConstants.BROADCAST_EXTRA_PAGE_LOAD_MS, 5678L);
    dispatchCheckoutBridgeIntent(plugin, CardConstants.BROADCAST_CHECKOUT_PAGE_LOADED, intent);

    assertTrue(called[0]);
    assertEquals(5678L, capturedMs[0]);
    assertTrue("page loaded must not clear presentation state", plugin.isCurrentlyPresented());
  }

  @Test
  public void dispatchPageLoaded_withNullListener_doesNotClearPresentation() throws Exception {
    plugin.setListener(null);

    Intent intent = new Intent(CardConstants.BROADCAST_CHECKOUT_PAGE_LOADED);
    intent.putExtra(CardConstants.BROADCAST_EXTRA_PAGE_LOAD_MS, 100L);
    dispatchCheckoutBridgeIntent(plugin, CardConstants.BROADCAST_CHECKOUT_PAGE_LOADED, intent);

    assertTrue("page loaded must not clear presentation state", plugin.isCurrentlyPresented());
  }

  private static void dispatchCheckoutBridgeIntent(
      StashNativePlugin plugin, String action, Intent intent) throws Exception {
    Method method =
        StashNativePlugin.class.getDeclaredMethod(
            "dispatchCheckoutBridgeIntent", String.class, Intent.class);
    method.setAccessible(true);
    intent.putExtra(StashCheckoutBridge.EXTRA_SESSION_ID, plugin.presentationSessionId);
    method.invoke(plugin, action, intent);
  }

  private static StashNative.StashNativeListener getListenerField(
      StashNativePlugin plugin) throws Exception {
    Field field = StashNativePlugin.class.getDeclaredField("listener");
    field.setAccessible(true);
    return (StashNative.StashNativeListener) field.get(plugin);
  }

  private static void setIsCurrentlyPresented(StashNativePlugin plugin, boolean value)
      throws Exception {
    Field field = StashNativePlugin.class.getDeclaredField("isCurrentlyPresented");
    field.setAccessible(true);
    field.setBoolean(plugin, value);
  }
}
