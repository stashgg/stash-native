package com.stash.stashnative;

import android.util.Log;
import android.view.View;
import java.lang.reflect.Constructor;

/** Keeps the checkout activity independent of optional camera and decoder classes. */
abstract class StashCodeLinkSession {
  static final int CAMERA_PERMISSION_REQUEST = 0x7371;

  static StashCodeLinkSession create(StashCheckoutActivity activity) {
    try {
      Class.forName("androidx.camera.camera2.Camera2Config");
      Class.forName("androidx.camera.lifecycle.ProcessCameraProvider");
      Class.forName("androidx.camera.view.PreviewView");
      Class.forName("com.google.zxing.qrcode.decoder.Decoder");
      Constructor<?> constructor = Class.forName("com.stash.stashnative.StashCodeLinkSupport")
          .getDeclaredConstructor(StashCheckoutActivity.class);
      constructor.setAccessible(true);
      return (StashCodeLinkSession) constructor.newInstance(activity);
    } catch (Throwable error) {
      Log.w("StashCodeLink",
          "CodeLink requires CameraX camera2, lifecycle, view, and ZXing core", error);
      return null;
    }
  }

  abstract View getView();

  abstract void setBottomInset(int inset);

  abstract void resume();

  abstract void pause();

  abstract void dispose();

  abstract void geometryChanged();

  abstract void permissionResult();

  abstract void showConnected(Runnable completion);
}
