package com.stash.stashnative.sample;

import static org.junit.Assert.*;
import android.app.Activity;
import android.app.Application;
import com.stash.stashnative.StashNative;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowLooper;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class RequestLifetimeTest {
  @Test public void oldHostDestroyCannotClearReplacementListener() {
    org.robolectric.android.controller.ActivityController<MainActivity> first =
        Robolectric.buildActivity(MainActivity.class).setup();
    org.robolectric.android.controller.ActivityController<MainActivity> second =
        Robolectric.buildActivity(MainActivity.class).setup();
    StashNative sdk = StashNative.getInstance();
    StashNative.StashNativeListener replacement = sdk.getListener();
    first.pause().stop().destroy();
    assertSame(replacement, sdk.getListener());
    second.pause().stop().destroy();
    assertNull(sdk.getListener());
  }

  @Test public void responseAfterDestroyCannotOpenCheckoutOnReplacementHost() throws Exception {
    CountDownLatch requested = new CountDownLatch(1);
    CountDownLatch respond = new CountDownLatch(1);
    ExecutorService serverWorker = Executors.newSingleThreadExecutor();
    ActivityController<MainActivity> controller = null;
    ActivityController<Activity> replacement = null;
    ExecutorService networkExecutor = null;
    Thread requestWorker = null;
    boolean destroyed = false;
    try (ServerSocket server = new ServerSocket(0)) {
      final Future<?> response = serverWorker.submit(() -> {
        try (Socket connection = server.accept()) {
          // Serve one request; reject any reconnect after the client cancels it.
          server.close();
          connection.setSoTimeout(5000);
          BufferedReader reader = new BufferedReader(new InputStreamReader(
              connection.getInputStream(), StandardCharsets.US_ASCII));
          int contentLength = -1;
          String line;
          while ((line = reader.readLine()) != null && !line.isEmpty()) {
            if (line.regionMatches(true, 0, "Content-Length:", 0, 15)) {
              contentLength = Integer.parseInt(line.substring(15).trim());
            }
          }
          assertNotNull("complete request headers", line);
          assertEquals("complete fixture POST body", 2, contentLength);
          assertEquals('{', reader.read());
          assertEquals('}', reader.read());
          requested.countDown();
          assertTrue("response released after host destruction",
              respond.await(5, TimeUnit.SECONDS));
          String body = "{\"url\":\"https://example.invalid/checkout\"}";
          String reply = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
              + "Content-Length: " + body.length() + "\r\nConnection: close\r\n\r\n" + body;
          try {
            connection.getOutputStream().write(reply.getBytes(StandardCharsets.US_ASCII));
          } catch (SocketException ignored) {
            // The destroyed host may already have disconnected this complete request.
          }
        }
        return null;
      });
      controller = Robolectric.buildActivity(MainActivity.class).setup();
      MainActivity activity = controller.get();
      Field executorField = MainActivity.class.getDeclaredField("networkExecutor");
      executorField.setAccessible(true);
      networkExecutor = (ExecutorService) executorField.get(activity);
      requestWorker = networkExecutor.submit(() -> Thread.currentThread()).get(5, TimeUnit.SECONDS);
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
      boolean received = requested.await(5, TimeUnit.SECONDS);
      if (!received && response.isDone()) {
        response.get();
      }
      assertTrue("local server received complete request", received);
      controller.pause().stop().destroy();
      destroyed = true;
      replacement = Robolectric.buildActivity(Activity.class).setup();
      respond.countDown();
      response.get(5, TimeUnit.SECONDS);
      assertTerminated(networkExecutor, requestWorker, "destroyed host request terminated");
      ShadowLooper.idleMainLooper();
      assertNull(Shadows.shadowOf(replacement.get()).getNextStartedActivity());
      assertFalse(StashNative.getInstance().isCurrentlyPresented());
    } finally {
      respond.countDown();
      if (controller != null && !destroyed) {
        controller.pause().stop().destroy();
      }
      if (replacement != null) {
        replacement.pause().stop().destroy();
      }
      StashNative.getInstance().resetPresentationState();
      serverWorker.shutdownNow();
      assertTrue("local server terminated",
          serverWorker.awaitTermination(5, TimeUnit.SECONDS));
      if (networkExecutor != null && !networkExecutor.isTerminated()) {
        networkExecutor.shutdownNow();
        assertTerminated(networkExecutor, requestWorker, "request cleanup terminated");
      }
    }
  }

  private static void assertTerminated(ExecutorService executor, Thread worker, String message)
      throws InterruptedException {
    if (executor.awaitTermination(5, TimeUnit.SECONDS)) {
      return;
    }
    StringBuilder diagnostic = new StringBuilder(message)
        .append("\nExecutor: ").append(executor)
        .append("\nRequest worker: ").append(worker == null ? "not captured" : worker.getName())
        .append("\nRuntime: ").append(System.getProperty("java.runtime.version"))
        .append(" on ").append(System.getProperty("os.name"));
    if (worker != null) {
      diagnostic.append("\nThread id=").append(worker.getId())
          .append(" state=").append(worker.getState())
          .append(" interrupted=").append(worker.isInterrupted());
      for (StackTraceElement frame : worker.getStackTrace()) {
        diagnostic.append("\n  at ").append(frame);
      }
    }
    fail(diagnostic.toString());
  }
}
