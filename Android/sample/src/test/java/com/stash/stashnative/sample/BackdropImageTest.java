package com.stash.stashnative.sample;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNotSame;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import android.graphics.Bitmap;
import android.net.Uri;
import androidx.exifinterface.media.ExifInterface;
import androidx.lifecycle.ViewModelStore;
import com.stash.stashnative.StashNativeCard;
import java.io.File;
import java.io.FileOutputStream;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowBitmapFactory;
import org.robolectric.util.ReflectionHelpers;

/** Image import, orientation, and ownership across repeated card presentations. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {21, 28})
public class BackdropImageTest {
  @Before
  public void rejectInvalidBitmapData() {
    ShadowBitmapFactory.setAllowInvalidImageData(false);
  }

  @Test
  public void sdkCleanupDoesNotDiscardSelectedImage() throws Exception {
    SampleBackdropImage image = load(writeImage(320, 160, Bitmap.CompressFormat.PNG));
    assertNotNull(image);
    Bitmap first = image.copy();
    StashNativeCard.setBackdropBitmap(first);
    StashNativeCard.setBackdropBitmap(null);
    assertTrue(first.isRecycled());
    Bitmap second = image.copy();
    assertNotNull(second);
    assertNotSame(first, second);
    assertEquals(320, second.getWidth());
    image.recycle();
    assertFalse(second.isRecycled());
    second.recycle();
  }

  @Test
  public void largeImagesAreDownsampled() throws Exception {
    SampleBackdropImage image = load(writeImage(5000, 1000, Bitmap.CompressFormat.PNG));
    assertNotNull(image);
    Bitmap copy = image.copy();
    assertTrue(copy.getWidth() <= 2400);
    assertEquals(5f, (float) copy.getWidth() / copy.getHeight(), 0.01f);
    copy.recycle();
    image.recycle();
  }

  @Test
  public void jpegOrientationIsApplied() throws Exception {
    File file = writeImage(320, 160, Bitmap.CompressFormat.JPEG);
    ExifInterface exif = new ExifInterface(file.getPath());
    exif.setAttribute(ExifInterface.TAG_ORIENTATION,
        String.valueOf(ExifInterface.ORIENTATION_ROTATE_90));
    exif.saveAttributes();
    SampleBackdropImage image = load(file);
    assertNotNull(image);
    Bitmap copy = image.copy();
    assertEquals(160, copy.getWidth());
    assertEquals(320, copy.getHeight());
    copy.recycle();
    image.recycle();
  }

  @Test
  public void corruptImageIsRejected() throws Exception {
    File file = File.createTempFile("invalid-backdrop", ".png",
        RuntimeEnvironment.getApplication().getCacheDir());
    try (FileOutputStream stream = new FileOutputStream(file)) {
      stream.write(new byte[] {0, 1, 2, 3});
    }
    assertNull(load(file));
  }

  @Test
  public void replacingAndClearingSelectionReleasesImages() throws Exception {
    MainViewModel model = new MainViewModel(RuntimeEnvironment.getApplication());
    ViewModelStore store = new ViewModelStore();
    store.put("sample", model);
    SampleBackdropImage first = load(writeImage(32, 16, Bitmap.CompressFormat.PNG));
    SampleBackdropImage second = load(writeImage(16, 32, Bitmap.CompressFormat.PNG));
    model.setBackdropImage(first);
    model.setBackdropImage(second);
    assertTrue(((Bitmap) ReflectionHelpers.getField(first, "bitmap")).isRecycled());
    model.setBackdropSource(MainViewModel.BackdropSource.SCREENSHOT);
    assertNotNull(model.getBackdropImage());
    Bitmap copy = model.getBackdropImage().copy();
    store.clear();
    assertTrue(((Bitmap) ReflectionHelpers.getField(second, "bitmap")).isRecycled());
    assertFalse(copy.isRecycled());
    copy.recycle();
  }

  private static SampleBackdropImage load(File file) {
    return SampleBackdropImage.load(RuntimeEnvironment.getApplication().getContentResolver(),
        Uri.fromFile(file));
  }

  private static File writeImage(int width, int height, Bitmap.CompressFormat format)
      throws Exception {
    String extension = format == Bitmap.CompressFormat.PNG ? ".png" : ".jpg";
    File file = File.createTempFile("backdrop", extension,
        RuntimeEnvironment.getApplication().getCacheDir());
    Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
    try (FileOutputStream stream = new FileOutputStream(file)) {
      assertTrue(bitmap.compress(format, 90, stream));
    } finally {
      bitmap.recycle();
    }
    return file;
  }
}
