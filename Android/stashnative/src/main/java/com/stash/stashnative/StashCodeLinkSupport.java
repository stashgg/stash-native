package com.stash.stashnative;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.graphics.Rect;
import android.graphics.RectF;
import android.hardware.display.DisplayManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.Settings;
import android.util.Size;
import android.view.Surface;
import androidx.annotation.NonNull;
import androidx.annotation.OptIn;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.CameraState;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.core.UseCaseGroup;
import androidx.camera.core.ViewPort;
import androidx.camera.core.resolutionselector.ResolutionSelector;
import androidx.camera.core.resolutionselector.ResolutionStrategy;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.camera.view.TransformExperimental;
import androidx.camera.view.transform.CoordinateTransform;
import androidx.camera.view.transform.ImageProxyTransformFactory;
import androidx.camera.view.transform.OutputTransform;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LifecycleRegistry;
import com.google.common.util.concurrent.ListenableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Owns camera permission, capture lifetime, scan geometry, and the confirmation hold. */
@OptIn(markerClass = TransformExperimental.class)
final class StashCodeLinkSupport implements LifecycleOwner, DisplayManager.DisplayListener {
  static final int CAMERA_PERMISSION_REQUEST = 0x7371;
  final StashCodeLinkView view;
  private final StashCheckoutActivity activity;
  private final Handler main = new Handler(Looper.getMainLooper());
  private final LifecycleRegistry lifecycle = new LifecycleRegistry(this);
  private final ExecutorService analysisExecutor = Executors.newSingleThreadExecutor();
  private final StashCodeLinkDecoder decoder = new StashCodeLinkDecoder();
  private final Runnable bind = this::bindCamera;
  private final DisplayManager displays;
  private ProcessCameraProvider provider;
  private Preview preview;
  private ImageAnalysis analysis;
  private Camera camera;
  private boolean providerPending;
  private boolean permissionRequested;
  private boolean errorReported;
  private boolean resumed;
  private boolean disposed;
  private boolean confirming;
  private volatile int generation;
  private volatile ScanRegion region;
  private long lastAnalysis;
  private int displayRotation = Surface.ROTATION_0;
  private Runnable connectedCompletion;
  private long holdRemaining;
  private long holdDeadline;
  private final Runnable finishConfirmation = () -> {
    Runnable completion = connectedCompletion;
    connectedCompletion = null;
    if (!disposed && resumed && completion != null) {
      completion.run();
    }
  };

  StashCodeLinkSupport(StashCheckoutActivity activity) {
    this.activity = activity;
    lifecycle.setCurrentState(Lifecycle.State.CREATED);
    displays = (DisplayManager) activity.getSystemService(Context.DISPLAY_SERVICE);
    view = new StashCodeLinkView(activity, activity::requestUserDismiss, this::openSettings);
    view.setGeometryListener(this::geometryChanged);
    view.preview.getPreviewStreamState().observe(this, stream -> {
      if (!disposed && !confirming && resumed && stream == PreviewView.StreamState.STREAMING) {
        view.cameraReady();
        updateRegion(generation);
      }
    });
  }

  @NonNull
  @Override
  public Lifecycle getLifecycle() {
    return lifecycle;
  }

  void resume() {
    if (disposed || resumed) {
      return;
    }
    resumed = true;
    if (confirming) {
      scheduleConfirmation();
      return;
    }
    if (displays != null) {
      displays.registerDisplayListener(this, main);
    }
    if (hasPermission()) {
      startAuthorized();
    } else if (!permissionDeclared()) {
      showError(StashNativeCard.CodeLinkError.CAMERA_PERMISSION_NOT_DECLARED);
    } else if (Build.VERSION.SDK_INT >= 23 && !permissionRequested) {
      permissionRequested = true;
      activity.requestPermissions(new String[] {Manifest.permission.CAMERA},
          CAMERA_PERMISSION_REQUEST);
    } else {
      showError(StashNativeCard.CodeLinkError.CAMERA_PERMISSION_DENIED);
    }
  }

  void permissionResult() {
    if (disposed || confirming) {
      return;
    }
    if (hasPermission()) {
      if (resumed) {
        startAuthorized();
      }
    } else {
      showError(StashNativeCard.CodeLinkError.CAMERA_PERMISSION_DENIED);
    }
  }

  private boolean hasPermission() {
    return ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA)
        == PackageManager.PERMISSION_GRANTED;
  }

  private boolean permissionDeclared() {
    try {
      PackageInfo info = activity.getPackageManager().getPackageInfo(
          activity.getPackageName(), PackageManager.GET_PERMISSIONS);
      if (info.requestedPermissions != null) {
        for (String permission : info.requestedPermissions) {
          if (Manifest.permission.CAMERA.equals(permission)) {
            return true;
          }
        }
      }
    } catch (PackageManager.NameNotFoundException expected) {
      return false;
    }
    return false;
  }

  private void startAuthorized() {
    lifecycle.setCurrentState(Lifecycle.State.RESUMED);
    view.showStatus(R.string.stash_code_link_starting, true, false);
    if (provider != null) {
      geometryChanged();
      return;
    }
    if (providerPending) {
      return;
    }
    providerPending = true;
    ListenableFuture<ProcessCameraProvider> future;
    try {
      future = ProcessCameraProvider.getInstance(activity);
    } catch (RuntimeException exception) {
      providerPending = false;
      showError(StashNativeCard.CodeLinkError.CAMERA_CONFIGURATION_FAILED);
      return;
    }
    future.addListener(() -> {
      providerPending = false;
      if (disposed) {
        return;
      }
      try {
        provider = future.get();
        geometryChanged();
      } catch (Exception exception) {
        showError(StashNativeCard.CodeLinkError.CAMERA_UNAVAILABLE);
      }
    }, main::post);
  }

  void geometryChanged() {
    generation++;
    region = null;
    main.removeCallbacks(bind);
    if (!disposed && resumed && !confirming && hasPermission()) {
      // The shared card can resize each frame. Bind once after its bounds settle.
      main.postDelayed(bind, 160);
    }
  }

  private void bindCamera() {
    if (disposed || !resumed || confirming || provider == null || !hasPermission()
        || view.getWidth() == 0 || view.getHeight() == 0) {
      return;
    }
    unbindCamera();
    final int epoch = ++generation;
    try {
      if (!provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)) {
        showError(StashNativeCard.CodeLinkError.CAMERA_UNAVAILABLE);
        return;
      }
      int rotation = view.getDisplay() == null
          ? Surface.ROTATION_0 : view.getDisplay().getRotation();
      displayRotation = rotation;
      ViewPort viewport = view.preview.getViewPort(rotation);
      if (viewport == null) {
        return;
      }
      preview = new Preview.Builder().setTargetRotation(rotation).build();
      preview.setSurfaceProvider(view.preview.getSurfaceProvider());
      analysis = new ImageAnalysis.Builder()
          .setTargetRotation(rotation)
          .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
          .setResolutionSelector(new ResolutionSelector.Builder()
              .setResolutionStrategy(new ResolutionStrategy(new Size(1280, 720),
                  ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)).build())
          .build();
      analysis.setAnalyzer(analysisExecutor, image -> analyze(image, epoch));
      UseCaseGroup group = new UseCaseGroup.Builder().setViewPort(viewport)
          .addUseCase(preview).addUseCase(analysis).build();
      camera = provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, group);
      camera.getCameraInfo().getCameraState().observe(this, state -> {
        if (epoch != generation || disposed || confirming) {
          return;
        }
        if (state.getError() != null) {
          showError(StashNativeCard.CodeLinkError.CAMERA_UNAVAILABLE);
        } else if (state.getType() == CameraState.Type.OPEN
            && view.preview.getPreviewStreamState().getValue()
                == PreviewView.StreamState.STREAMING) {
          view.cameraReady();
        }
      });
    } catch (SecurityException exception) {
      showError(StashNativeCard.CodeLinkError.CAMERA_PERMISSION_DENIED);
    } catch (RuntimeException | androidx.camera.core.CameraInfoUnavailableException exception) {
      showError(StashNativeCard.CodeLinkError.CAMERA_CONFIGURATION_FAILED);
    }
  }

  private void updateRegion(int epoch) {
    if (epoch != generation || disposed || !resumed || confirming) {
      return;
    }
    OutputTransform target = view.preview.getOutputTransform();
    RectF frame = view.scanFrame();
    frame.inset(2, 2);
    if (target != null && frame.width() > 0 && frame.height() > 0) {
      region = new ScanRegion(target, frame);
    }
  }

  private void analyze(ImageProxy image, int epoch) {
    try {
      if (epoch != generation) {
        return;
      }
      ScanRegion snapshot = region;
      if (snapshot == null) {
        main.post(() -> updateRegion(epoch));
        return;
      }
      long now = SystemClock.uptimeMillis();
      if (now - lastAnalysis < 120) {
        return;
      }
      lastAnalysis = now;
      RectF crop = new RectF(snapshot.frame);
      ImageProxyTransformFactory factory = new ImageProxyTransformFactory();
      new CoordinateTransform(snapshot.transform, factory.getOutputTransform(image)).mapRect(crop);
      Rect pixels = new Rect((int) Math.ceil(crop.left), (int) Math.ceil(crop.top),
          (int) Math.floor(crop.right), (int) Math.floor(crop.bottom));
      ImageProxy.PlaneProxy plane = image.getPlanes()[0];
      String content = decoder.decode(plane.getBuffer(), image.getWidth(), image.getHeight(),
          plane.getRowStride(), plane.getPixelStride(), pixels);
      if (content != null) {
        main.post(() -> {
          if (epoch == generation && snapshot == region && resumed && !disposed && !confirming) {
            activity.completeCodeLink(content);
          }
        });
      }
    } catch (RuntimeException expected) {
      // A frame invalidated by a camera reconfiguration is skipped.
    } finally {
      image.close();
    }
  }

  void showConnected(Runnable completion) {
    confirming = true;
    generation++;
    region = null;
    main.removeCallbacks(bind);
    holdRemaining = view.showConnected();
    unbindCamera();
    connectedCompletion = completion;
    scheduleConfirmation();
  }

  private void scheduleConfirmation() {
    main.removeCallbacks(finishConfirmation);
    if (resumed && connectedCompletion != null) {
      holdDeadline = SystemClock.uptimeMillis() + holdRemaining;
      main.postDelayed(finishConfirmation, holdRemaining);
    }
  }

  private void showError(StashNativeCard.CodeLinkError error) {
    if (disposed || confirming || activity.isDismissing) {
      return;
    }
    boolean denied = error == StashNativeCard.CodeLinkError.CAMERA_PERMISSION_DENIED;
    view.showStatus(denied ? R.string.stash_code_link_permission
        : R.string.stash_code_link_unavailable, false, denied);
    if (!errorReported) {
      errorReported = true;
      StashCheckoutBridge.emitCodeLinkError(activity, error);
    }
  }

  private void openSettings() {
    try {
      activity.startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
          Uri.parse("package:" + activity.getPackageName())));
    } catch (RuntimeException expected) {
      showError(StashNativeCard.CodeLinkError.CAMERA_UNAVAILABLE);
    }
  }

  void pause() {
    if (resumed && confirming && connectedCompletion != null) {
      holdRemaining = Math.max(0, holdDeadline - SystemClock.uptimeMillis());
    }
    resumed = false;
    generation++;
    region = null;
    main.removeCallbacks(bind);
    main.removeCallbacks(finishConfirmation);
    if (displays != null) {
      displays.unregisterDisplayListener(this);
    }
    if (!disposed) {
      lifecycle.setCurrentState(Lifecycle.State.CREATED);
    }
    unbindCamera();
  }

  private void unbindCamera() {
    if (camera != null) {
      camera.getCameraInfo().getCameraState().removeObservers(this);
      camera = null;
    }
    if (analysis != null) {
      analysis.clearAnalyzer();
    }
    if (provider != null && preview != null && analysis != null) {
      // Never unbind use cases belonging to the host game.
      provider.unbind(preview, analysis);
    }
    preview = null;
    analysis = null;
    region = null;
  }

  void dispose() {
    if (disposed) {
      return;
    }
    pause();
    disposed = true;
    connectedCompletion = null;
    lifecycle.setCurrentState(Lifecycle.State.DESTROYED);
    view.dispose();
    analysisExecutor.shutdown();
  }

  @Override public void onDisplayChanged(int displayId) {
    if (view.getDisplay() != null && displayId == view.getDisplay().getDisplayId()
        && displayRotation != view.getDisplay().getRotation()) {
      geometryChanged();
    }
  }

  @Override public void onDisplayAdded(int displayId) {}

  @Override public void onDisplayRemoved(int displayId) {}

  private static final class ScanRegion {
    final OutputTransform transform;
    final RectF frame;

    ScanRegion(OutputTransform transform, RectF frame) {
      this.transform = transform;
      this.frame = frame;
    }
  }
}
