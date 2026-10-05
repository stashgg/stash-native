package com.stash.stashnative.sample;

import static org.junit.Assert.*;
import android.app.Activity;
import android.app.Application;
import com.stash.stashnative.StashNativeCard;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowLooper;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class RequestLifetimeTest {
  @Test public void responseAfterDestroyCannotOpenCheckoutOnReplacementHost() throws Exception {
    CountDownLatch requested = new CountDownLatch(1);
    CountDownLatch respond = new CountDownLatch(1);
    ExecutorService serverWorker = Executors.newSingleThreadExecutor();
    try (ServerSocket server = new ServerSocket(0)) {
      serverWorker.submit(() -> {
        try (Socket connection = server.accept()) {
          BufferedReader reader = new BufferedReader(new InputStreamReader(
              connection.getInputStream(), StandardCharsets.US_ASCII));
          while (!reader.readLine().isEmpty()) { /* Consume request headers. */ }
          requested.countDown();
          respond.await(5, TimeUnit.SECONDS);
          String body = "{\"url\":\"https://example.invalid/checkout\"}";
          String response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
              + "Content-Length: " + body.length() + "\r\nConnection: close\r\n\r\n" + body;
          connection.getOutputStream().write(response.getBytes(StandardCharsets.US_ASCII));
        } catch (Exception ignored) {
          // Disconnecting the in-flight request is an expected cancellation result.
        }
      });
      org.robolectric.android.controller.ActivityController<MainActivity> controller =
          Robolectric.buildActivity(MainActivity.class).setup();
      MainActivity activity = controller.get();
      MainViewModel model = new MainViewModel((Application) activity.getApplicationContext()) {
        @Override public String getApiBaseUrl() {
          return "http://127.0.0.1:" + server.getLocalPort();
        }
      };
      Field modelField = MainActivity.class.getDeclaredField("viewModel");
      modelField.setAccessible(true);
      modelField.set(activity, model);
      Method request = MainActivity.class.getDeclaredMethod("generateAndOpen", String.class,
          String.class, boolean.class, int.class, String.class);
      request.setAccessible(true);
      request.invoke(activity, "/fixture", "{}", false, R.string.error_generate_checkout_url, "fixture");
      assertTrue("local server received request", requested.await(5, TimeUnit.SECONDS));
      controller.pause().stop().destroy();
      Activity replacement = Robolectric.buildActivity(Activity.class).setup().get();
      StashNativeCard.getInstance().setActivity(replacement);
      respond.countDown();
      Field executorField = MainActivity.class.getDeclaredField("networkExecutor");
      executorField.setAccessible(true);
      assertTrue(((ExecutorService) executorField.get(activity)).awaitTermination(5, TimeUnit.SECONDS));
      ShadowLooper.idleMainLooper();
      assertNull(Shadows.shadowOf(replacement).getNextStartedActivity());
      assertFalse(StashNativeCard.getInstance().isCurrentlyPresented());
      StashNativeCard.getInstance().resetPresentationState();
      replacement.finish();
    } finally {
      respond.countDown();
      serverWorker.shutdownNow();
    }
  }
}
