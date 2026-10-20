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

  /** What happens to the host relative to the generate response. */
  private enum Host {
    ALIVE, DESTROYED_BEFORE_RESPONSE, DESTROYED_AFTER_RESPONSE, MANUAL_OPEN_BEFORE_RESPONSE
  }

  /** A completion that arrives while the host is alive reaches the UI branch and opens a card. */
  @Test public void responseWhileHostIsAliveOpensCheckoutOnce() throws Exception {
    MainActivity activity = generateWithLocalServer(Host.ALIVE);
    assertEquals(1, activity.acceptedCompletions);
    assertEquals(1, activity.cardOpenRequests);
    assertNotNull(Shadows.shadowOf(activity).getNextStartedActivity());
  }

  /** Destroying the host cancels the request itself, so no completion is ever produced. */
  @Test public void destroyBeforeResponseCancelsTheRequest() throws Exception {
    MainActivity activity = generateWithLocalServer(Host.DESTROYED_BEFORE_RESPONSE);
    assertEquals(0, activity.acceptedCompletions);
    assertEquals(0, activity.cardOpenRequests);
    assertNull(Shadows.shadowOf(activity).getNextStartedActivity());
  }

  /**
   * Discriminating form of the A-010 guard test: the response is parsed and posted to the main
   * thread before the host stops and is destroyed, so only the onStop supersession, the UI-thread
   * lifetime guard and presentCard's guard stand between the stale completion and the counters.
   */
  @Test public void responseAfterDestroyCannotOpenCheckoutOnReplacementHost() throws Exception {
    MainActivity activity = generateWithLocalServer(Host.DESTROYED_AFTER_RESPONSE);
    assertEquals(0, activity.acceptedCompletions);
    assertEquals(0, activity.cardOpenRequests);
    assertNull(Shadows.shadowOf(activity).getNextStartedActivity());
  }

  /**
   * A-096: opening the URL row's card while a generate request is pending supersedes it, so the
   * late response cannot open a second, unrequested checkout.
   */
  @Test public void manualOpenSupersedesPendingGenerate() throws Exception {
    MainActivity activity = generateWithLocalServer(Host.MANUAL_OPEN_BEFORE_RESPONSE);
    assertEquals(0, activity.acceptedCompletions);
    assertEquals(1, activity.cardOpenRequests);
    assertNull(Shadows.shadowOf(activity).getNextStartedActivity());
  }

  /** A-102: a selected instance without an app ID reports it instead of signing as the demo. */
  @Test public void blankSelectedAppIdShowsRequiredFieldsWithoutRequest() throws Exception {
    ActivityController<MainActivity> controller =
        Robolectric.buildActivity(MainActivity.class).setup();
    try {
      MainActivity activity = controller.get();
      MainViewModel model = org.robolectric.util.ReflectionHelpers.getField(activity, "viewModel");
      model.openInstanceDetails(model.getSelectedApiKey().id);
      model.setEditingAppId(" ");
      model.navigateTo(MainViewModel.Screen.TEST);
      assertEquals("", model.getActiveAppId());
      Method request = MainActivity.class.getDeclaredMethod("generateAndOpen", String.class,
          String.class, boolean.class, int.class, String.class);
      request.setAccessible(true);
      request.invoke(activity, "/fixture", "{}", false, R.string.error_generate_checkout_url,
          "fixture");
      assertNull(pendingRequest(activity));
      android.app.AlertDialog dialog =
          org.robolectric.shadows.ShadowAlertDialog.getLatestAlertDialog();
      assertNotNull(dialog);
      assertEquals(activity.getString(R.string.add_api_key_incomplete),
          Shadows.shadowOf(dialog).getMessage().toString());
    } finally {
      controller.pause().stop().destroy();
    }
  }

  /**
   * Serves one generate request from a local socket, destroys the host at the requested point,
   * and returns the (possibly destroyed) host after the main looper drained the completion.
   */
  private MainActivity generateWithLocalServer(Host hostLifetime) throws Exception {
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
      if (hostLifetime == Host.DESTROYED_BEFORE_RESPONSE) {
        controller.pause().stop().destroy();
        destroyed = true;
        replacement = Robolectric.buildActivity(Activity.class).setup();
      } else if (hostLifetime == Host.MANUAL_OPEN_BEFORE_RESPONSE) {
        Method openCard = MainActivity.class.getDeclaredMethod("openCard");
        openCard.setAccessible(true);
        openCard.invoke(activity);
        assertNotNull("manual open starts checkout",
            Shadows.shadowOf(activity).getNextStartedActivity());
      }
      respond.countDown();
      response.get(5, TimeUnit.SECONDS);
      if (hostLifetime == Host.DESTROYED_BEFORE_RESPONSE) {
        assertTerminated(networkExecutor, requestWorker, "destroyed host request terminated");
      } else if (hostLifetime == Host.MANUAL_OPEN_BEFORE_RESPONSE) {
        // The superseded worker finishes before this marker runs on the single-thread executor.
        networkExecutor.submit(() -> null).get(5, TimeUnit.SECONDS);
      } else {
        // The worker has parsed the response and posted the completion; the looper is paused.
        pendingRequest(activity).get(5, TimeUnit.SECONDS);
      }
      if (hostLifetime == Host.DESTROYED_AFTER_RESPONSE) {
        controller.pause().stop().destroy();
        destroyed = true;
        replacement = Robolectric.buildActivity(Activity.class).setup();
      }
      ShadowLooper.idleMainLooper();
      if (replacement != null) {
        assertNull(Shadows.shadowOf(replacement.get()).getNextStartedActivity());
      }
      return activity;
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

  private static Future<?> pendingRequest(MainActivity activity) throws Exception {
    Field field = MainActivity.class.getDeclaredField("pendingRequest");
    field.setAccessible(true);
    return (Future<?>) field.get(activity);
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
