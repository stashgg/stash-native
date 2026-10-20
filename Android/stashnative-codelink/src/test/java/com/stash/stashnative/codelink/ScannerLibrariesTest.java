package com.stash.stashnative.codelink;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import org.junit.Test;

/**
 * A partial installation must fail while the core resolves the module, so it reports
 * SCANNER_UNAVAILABLE before a card opens. Each case loads the module in a class loader that
 * hides one library.
 */
public class ScannerLibrariesTest {
  private static final String MODULE = "com.stash.stashnative.codelink.StashScannerSupport";

  @Test public void completeInstallationInitializesModule() throws Exception {
    assertEquals(MODULE, Class.forName(MODULE, true, new HidingLoader(null)).getName());
  }

  @Test public void eachMissingLibraryFailsModuleInitialization() {
    String[] libraries = {
      "androidx.camera.camera2.",
      "androidx.camera.lifecycle.",
      "androidx.camera.core.",
      "androidx.camera.view.",
      "androidx.lifecycle.LifecycleRegistry",
      "com.google.common.util.concurrent.ListenableFuture",
      "com.google.zxing.",
    };
    for (String library : libraries) {
      try {
        Class.forName(MODULE, true, new HidingLoader(library));
        fail("Module initialized without " + library);
      } catch (ClassNotFoundException | LinkageError expected) {
        // NoClassDefFoundError or ExceptionInInitializerError: the core's catch reports both.
      }
    }
  }

  /** Defines application classes itself so a hidden library cannot come from the parent. */
  private static final class HidingLoader extends ClassLoader {
    private final String hidden;

    HidingLoader(String hidden) {
      super(ScannerLibrariesTest.class.getClassLoader());
      this.hidden = hidden;
    }

    @Override
    protected synchronized Class<?> loadClass(String name, boolean resolve)
        throws ClassNotFoundException {
      if (hidden != null && name.startsWith(hidden)) {
        throw new ClassNotFoundException(name);
      }
      Class<?> type = findLoadedClass(name);
      if (type == null) {
        byte[] bytes = name.startsWith("java.") || name.startsWith("android.")
            ? null : read(name.replace('.', '/') + ".class");
        if (bytes == null) {
          return super.loadClass(name, resolve);
        }
        type = defineClass(name, bytes, 0, bytes.length);
      }
      if (resolve) {
        resolveClass(type);
      }
      return type;
    }

    private byte[] read(String path) {
      try (InputStream in = getParent().getResourceAsStream(path)) {
        if (in == null) {
          return null;
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        for (int count; (count = in.read(buffer)) != -1; ) {
          out.write(buffer, 0, count);
        }
        return out.toByteArray();
      } catch (IOException error) {
        return null;
      }
    }
  }
}
