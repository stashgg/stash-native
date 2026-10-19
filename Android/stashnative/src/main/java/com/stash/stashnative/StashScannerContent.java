package com.stash.stashnative;

import android.util.Log;
import android.view.View;
import java.lang.reflect.Constructor;

/**
 * Scanner surface hosted by the card. SPI for the optional {@code stashnative-codelink} module,
 * not a host API: the core resolves {@code com.stash.stashnative.codelink.StashScannerSupport}
 * through its public {@code (StashScannerHost)} constructor and treats any failure as
 * {@link StashNative.ScannerError#SCANNER_UNAVAILABLE}.
 */
public abstract class StashScannerContent {
  /** Request code the scanner passes to {@code Activity.requestPermissions}. */
  public static final int CAMERA_PERMISSION_REQUEST = 0x7371;

  static final String MODULE_CLASS = "com.stash.stashnative.codelink.StashScannerSupport";

  static StashScannerContent create(StashScannerHost host) {
    try {
      Class<?> type = Class.forName(MODULE_CLASS);
      if (!StashScannerContent.class.isAssignableFrom(type)) {
        throw new ClassCastException(MODULE_CLASS + " is not a StashScannerContent");
      }
      Constructor<?> constructor = type.getConstructor(StashScannerHost.class);
      return (StashScannerContent) constructor.newInstance(host);
    } catch (Throwable error) {
      Log.w("StashNative", "QR Code Linking requires the stashnative-codelink module with "
          + "CameraX camera2, lifecycle, view, and ZXing core", error);
      return null;
    }
  }

  /** The scanner chrome the card adds as its content. */
  public abstract View getView();

  /** Bottom system inset the scanner's controls must avoid. */
  public abstract void setBottomInset(int inset);

  public abstract void resume();

  public abstract void pause();

  public abstract void dispose();

  /** The card changed size, rotation, or display; rebind capture once bounds settle. */
  public abstract void geometryChanged();

  /** The host answered the {@link #CAMERA_PERMISSION_REQUEST} prompt. */
  public abstract void permissionResult();

  /** Freeze the preview, show the connected state, then run completion after the hold. */
  public abstract void showConnected(Runnable completion);
}
